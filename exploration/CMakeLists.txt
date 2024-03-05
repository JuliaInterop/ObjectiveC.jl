cmake_minimum_required(VERSION 3.24)
project(exploration)
project(exploration VERSION 0.1 DESCRIPTION "Objective C exploration"
        LANGUAGES CXX OBJC)
set(CMAKE_CXX_STANDARD 20)

find_library(FOUNDATION Foundation)

function (objc_demo name)
    add_executable(${name} ${name}.mm)
    target_link_libraries(${name} ${FOUNDATION})
endfunction()

objc_demo(000_test_compile)
objc_demo(010_list_classes)