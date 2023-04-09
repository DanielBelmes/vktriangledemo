import glm/[mat, vec]
import application

if isMainModule:
  var app: HelloWorldApp = new HelloWorldApp

  try:
    app.run()
  except CatchableError:
    echo getCurrentExceptionMsg()
    quit(-1)

  var matrix: Mat4[uint32]
  var vec: Vec4[uint32]
  var test = matrix * vec