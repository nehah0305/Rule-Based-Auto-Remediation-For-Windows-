cmake_minimum_required(VERSION 3.14)
project(remediation_frontend LANGUAGES CXX)

set(FLUTTER_FRAMEWORK_DIR "${FLUTTER_ROOT}/bin/cache/artifacts/engine/windows-x64")

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /W4 /WX /EHsc")

add_executable(${PROJECT_NAME}
  "runner/flutter.cpp"
  "runner/main.cpp"
  "runner/utils.cpp"
  "runner/win32_window.cpp"
)
target_link_libraries(${PROJECT_NAME} PRIVATE flutter flutter_wrapper_app)
