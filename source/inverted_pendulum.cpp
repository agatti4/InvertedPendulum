#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/pwm.h>
#include <zephyr/drivers/sensor.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

#include <math.h>

LOG_MODULE_REGISTER(pend, LOG_LEVEL_INF);

/***************************************************************************
 * Control constants
 **************************************************************************/
static constexpr float BALANCE_KP = 5.0f;
static constexpr float BALANCE_KI = 3.0f;
static constexpr float BALANCE_KD = 0.075f;
static constexpr float CENTER_KP = 0.15f;
static constexpr float CENTER_KI = -0.3f;
static constexpr float CENTER_KD = 0.0f;
static constexpr float INTEGRALMAX = 20.0f;
static constexpr float INTEGRALMIN = -20.0f;
static constexpr float PENDULUMTOOFAR = 333.0f; // ~30 degrees from vertical
static constexpr float SAMPLETIME = 0.001f;     // 1 ms

static constexpr float PENDULUM_FULL_SCALE_COUNTS = 4000.0f;
static constexpr float PENDULUM_CENTER_OFFSET = 2000.0f;

/***************************************************************************
 * Devicetree handles
 **************************************************************************/
static const struct device *qdec_pendulum = DEVICE_DT_GET(DT_ALIAS(qdec1)); // TIM1
static const struct device *qdec_motor = DEVICE_DT_GET(DT_ALIAS(qdec0));    // TIM8

static const struct pwm_dt_spec motor_pwm = PWM_DT_SPEC_GET(DT_ALIAS(motor_pwm));

static const struct gpio_dt_spec motor_dir = GPIO_DT_SPEC_GET(DT_ALIAS(motor_dir), gpios);

static const struct gpio_dt_spec motor_inhibit = GPIO_DT_SPEC_GET(DT_ALIAS(motor_inhibit), gpios);

/***************************************************************************
 * Debug outputs
 **************************************************************************/
volatile float debug_float0 = 0.0f;
volatile float debug_float1 = 0.0f;
volatile float debug_float2 = 0.0f;
volatile float debug_float3 = 0.0f;

/***************************************************************************
 * 1 kHz scheduling primitives
 **************************************************************************/
static void Timer1msExpiry(struct k_timer *timer);

K_SEM_DEFINE(process_wait_sem, 0, 1);
K_TIMER_DEFINE(timer_1ms, Timer1msExpiry, nullptr);

static void Timer1msExpiry(struct k_timer *timer)
{
    ARG_UNUSED(timer);
    k_sem_give(&process_wait_sem);
}

/***************************************************************************
 *
 * Function: ReadPendulumPosition
 *
 * Description: Reads the pendulum quadrature encoder (TIM1 / qdec1) and
 *              returns the centered position in the original count domain.
 *
 **************************************************************************/
static float ReadPendulumPosition(void)
{
    struct sensor_value val;
    int32_t raw_pend_count = 0;
    float wrapped_pend = 0.0f;

    sensor_sample_fetch_chan(qdec_pendulum, SENSOR_CHAN_ENCODER_COUNT);
    sensor_channel_get(qdec_pendulum, SENSOR_CHAN_ENCODER_COUNT, &val);

    raw_pend_count = val.val1;

    wrapped_pend = fmodf((float)raw_pend_count, (float)PENDULUM_FULL_SCALE_COUNTS);
    if (wrapped_pend < 0.0f)
    {
        wrapped_pend += (float)PENDULUM_FULL_SCALE_COUNTS;
    }

    return wrapped_pend;
}

/***************************************************************************
 *
 * Function: ReadMotorEncoder
 *
 * Description: Reads the motor/cart quadrature encoder (TIM8 / qdec0) as a
 *              raw, non-wrapped counter value and reinterprets the low 16
 *              bits as signed
 *
 **************************************************************************/
static int32_t ReadMotorEncoder(void)
{
    static int32_t total_count = 0;
    static int32_t previous_count = 0;
    static bool initialized = false;

    struct sensor_value val;

    sensor_sample_fetch_chan(qdec_motor, SENSOR_CHAN_ENCODER_COUNT);
    sensor_channel_get(qdec_motor, SENSOR_CHAN_ENCODER_COUNT, &val);

    int32_t current_count = val.val1;

    // Keep the hardware count in the range 0..4095
    current_count &= 0xFFF;

    if (!initialized)
    {
        previous_count = current_count;
        initialized = true;
        total_count = 0;
        return 0;
    }

    int32_t delta = current_count - previous_count;

    // Counter wrapped forward: 4095 -> 0
    if (delta < -2048)
    {
        delta += 4096;
    }
    // Counter wrapped backward: 0 -> 4095
    else if (delta > 2048)
    {
        delta -= 4096;
    }

    total_count += delta;
    previous_count = current_count;

    return total_count;
}

/***************************************************************************
 *
 * Function: MotorOutput
 *
 * Description: Takes a value from -1 to 1 and drives the motor direction
 *              GPIO, PWM duty cycle, and enable/inhibit GPIO accordingly.
 *
 * Parameters: float with values -1 to 1
 *
 **************************************************************************/
static void MotorOutput(float outputPWM)
{
    // Check if the maximums are exceeded
    if (outputPWM > 1.0f)
    {
        outputPWM = 1.0f;
    }
    else if (outputPWM < -1.0f)
    {
        outputPWM = -1.0f;
    }

    // Set the direction bit
    gpio_pin_set_dt(&motor_dir, outputPWM > 0.0f ? 1 : 0);

    // Set the motor PWM duty cycle
    uint32_t pulse_ns = static_cast<uint32_t>(fabsf(outputPWM) * motor_pwm.period);
    pwm_set_pulse_dt(&motor_pwm, pulse_ns);

    // Enable the motor
    gpio_pin_set_dt(&motor_inhibit, 1);
}

/***************************************************************************
 *
 * Function: PendControlStep
 *
 * Description: This function should be called every 1ms to perform the
 *              motor control.
 *
 **************************************************************************/
static void PendControlStep(void)
{
    float controloutput = 0.0f;
    float center_proportional = 0.0f;
    static float center_integral = 0.0f;
    float center_derivative = 0.0f;
    static float center_last_proportional = 0.0f;
    static float center_bias = 0.0f;
    float pendulumposition = 0.0f;
    float balance_proportional = 0.0f;
    static float balance_integral = 0.0f;
    float balance_derivative = 0.0f;
    static float balance_last_proportional = 0.0f;

    int32_t motorencoder = ReadMotorEncoder();
    pendulumposition = ReadPendulumPosition() - PENDULUM_CENTER_OFFSET;

    // Check if we should give up trying to balance because the pendulum is
    // more than 30 degrees off vertical
    if ((pendulumposition < -PENDULUMTOOFAR) || (pendulumposition > PENDULUMTOOFAR))
    {
        controloutput = 0.0f;
        // prevent derivative kick / integral windup on recovery
        balance_last_proportional = 0.0f - pendulumposition;
        center_last_proportional = 0.0f - static_cast<float>(motorencoder);
        balance_integral = 0.0f;
        center_integral = 0.0f;
    }
    else
    {

        //*******************************************************************
        // Control the motor to center the pendulum
        //*******************************************************************

        center_proportional = 0.0f - static_cast<float>(motorencoder);

        center_integral = center_integral + center_proportional * SAMPLETIME;

        if (center_integral > INTEGRALMAX)
        {
            center_integral = INTEGRALMAX;
        }
        else if (center_integral < INTEGRALMIN)
        {
            center_integral = INTEGRALMIN;
        }

        center_derivative = (center_proportional - center_last_proportional) / SAMPLETIME;
        center_last_proportional = center_proportional;

        center_bias = CENTER_KP * center_proportional + CENTER_KI * center_integral + CENTER_KD * center_derivative;

        //*******************************************************************
        // Control the motor to balance the pendulum
        //*******************************************************************

        balance_proportional = 0.0f - pendulumposition - center_bias;

        balance_integral = balance_integral + balance_proportional * SAMPLETIME;

        if (balance_integral > INTEGRALMAX)
        {
            balance_integral = INTEGRALMAX;
        }
        else if (balance_integral < INTEGRALMIN)
        {
            balance_integral = INTEGRALMIN;
        }

        balance_derivative = (balance_proportional - balance_last_proportional) / SAMPLETIME;
        balance_last_proportional = balance_proportional;

        controloutput =
            BALANCE_KP * balance_proportional + BALANCE_KI * balance_integral + BALANCE_KD * balance_derivative;

        if (controloutput > 1000.0f)
        {
            controloutput = 1000.0f;
        }
        else if (controloutput < -1000.0f)
        {
            controloutput = -1000.0f;
        }
        controloutput = controloutput / 1000.0f;
    }

    MotorOutput(controloutput);

    debug_float0 = BALANCE_KP * balance_proportional;
    debug_float1 = BALANCE_KI * balance_integral;
    debug_float2 = BALANCE_KD * balance_derivative;
    debug_float3 = controloutput;
}

/***************************************************************************
 * Control thread: waits for the 1 ms tick and runs one control step
 **************************************************************************/
static void PendControlThread(void *, void *, void *)
{
    for (;;)
    {
        k_sem_take(&process_wait_sem, K_FOREVER);
        PendControlStep();
    }
}

K_THREAD_DEFINE(pend_control_tid, 2048, PendControlThread, nullptr, nullptr, nullptr, K_PRIO_PREEMPT(2), 0, 0);

/***************************************************************************
 *
 * Function: pend_init
 *
 * Description: Verifies devices are ready, configures GPIOs, and starts the
 *              PWM output and the 1 ms control timer.
 *
 **************************************************************************/
int pend_init(void)
{
    if (!device_is_ready(qdec_pendulum))
    {
        LOG_ERR("Pendulum qdec device not ready");
        return -ENODEV;
    }
    if (!device_is_ready(qdec_motor))
    {
        LOG_ERR("Motor qdec device not ready");
        return -ENODEV;
    }
    if (!device_is_ready(motor_pwm.dev))
    {
        LOG_ERR("Motor PWM device not ready");
        return -ENODEV;
    }
    if (!gpio_is_ready_dt(&motor_dir))
    {
        LOG_ERR("Motor direction GPIO not ready");
        return -ENODEV;
    }
    if (!gpio_is_ready_dt(&motor_inhibit))
    {
        LOG_ERR("Motor inhibit/enable GPIO not ready");
        return -ENODEV;
    }

    int ret;

    ret = gpio_pin_configure_dt(&motor_dir, GPIO_OUTPUT_INACTIVE);
    if (ret < 0)
    {
        LOG_ERR("Failed to configure motor direction GPIO (%d)", ret);
        return ret;
    }

    ret = gpio_pin_configure_dt(&motor_inhibit, GPIO_OUTPUT_INACTIVE);
    if (ret < 0)
    {
        LOG_ERR("Failed to configure motor inhibit/enable GPIO (%d)", ret);
        return ret;
    }

    // Start the PWM output at 0% duty
    ret = pwm_set_pulse_dt(&motor_pwm, 0);
    if (ret < 0)
    {
        LOG_ERR("Failed to start motor PWM (%d)", ret);
        return ret;
    }

    // Start the 1 ms periodic control tick
    k_timer_start(&timer_1ms, K_MSEC(1), K_MSEC(1));

    LOG_INF("Inverted pendulum control initialized");

    return 0;
}

SYS_INIT(pend_init, APPLICATION, CONFIG_APPLICATION_INIT_PRIORITY);