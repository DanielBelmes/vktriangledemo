import nimgl/[vulkan, glfw]
import glm/[mat, vec]
import application

if isMainModule:
  var app: HelloWorldApp = HelloWorldApp()

  try:
    app.run()
  except:
    echo getCurrentExceptionMsg()
    quit(-1)

  var matrix: Mat4[uint32]
  var vec: Vec4[uint32]
  var test = matrix * vec
  echo test