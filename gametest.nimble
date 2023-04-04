# Package

version       = "0.0.1"
author        = "DanielBelmes"
description   = "wave function collapse"
license       = "MIT"
srcDir        = "src"
bin           = @["gametest"]


# Dependencies

requires "nim >= 1.6.8"
requires "nimgl >= 1.0.0"
requires "glm >= 1.0.0"
requires "vulkan"

before build:
  exec("glslc src/shaders/shader.vert -o src/shaders/vert.spv")
  exec("glslc src/shaders/shader.frag -o src/shaders/frag.spv")