# Package

version       = "0.0.1"
author        = "DanielBelmes"
description   = "wave function collapse"
license       = "MIT"
srcDir        = "src"
binDir        = "build"
backend       = "c"
bin           = @["gametest"]


# Dependencies

requires "nim >= 1.6.8"
requires "glm >= 1.0.0"
requires "https://github.com/DanielBelmes/glfw#head"
requires "https://github.com/DanielBelmes/vulkan#head"

before build:
  exec("glslc src/shaders/shader.vert -o src/shaders/vert.spv")
  exec("glslc src/shaders/shader.frag -o src/shaders/frag.spv")

task clean, "Cleans binaries":
  echo "❯ Removing Build Dir"
  exec("rm -rf ./build")