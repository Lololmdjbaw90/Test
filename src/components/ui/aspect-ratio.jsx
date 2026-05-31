import * as React from "react"

// Dependency-free AspectRatio. Canonical shadcn re-exports @radix-ui/react-aspect-ratio,
// which is not installed in this project; this keeps the same { ratio } API.
const AspectRatio = React.forwardRef(({ ratio = 1, style, children, ...props }, ref) => (
  <div ref={ref} style={{ position: "relative", width: "100%", paddingBottom: `${100 / ratio}%`, ...style }} {...props}>
    <div style={{ position: "absolute", inset: 0 }}>{children}</div>
  </div>
))
AspectRatio.displayName = "AspectRatio"
export { AspectRatio }
