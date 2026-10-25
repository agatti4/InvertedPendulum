cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(InvertedPendulum)

target_sources(app PRIVATE source/inverted_pendulum.cpp)
