export class ShaderProgram {
  readonly vertexSource: string
  readonly fragmentSource: string | none = none
  readonly vertexFunction: string = "main"
  readonly fragmentFunction: string = "main"
}
