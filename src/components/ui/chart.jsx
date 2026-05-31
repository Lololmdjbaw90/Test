import * as React from "react"

// Placeholder for an unused shadcn/ui component.
// The canonical implementation depends on the npm package: recharts
// which is NOT installed in this project. To use this component for real:
//   1) npm install recharts
//   2) replace this file with the official shadcn/ui source for it.
// This passthrough keeps imports valid and the build green in the meantime.
const Passthrough = React.forwardRef(({ children }, ref) => React.createElement(React.Fragment, null, children))
Passthrough.displayName = "ShadcnPlaceholder"
export const ChartContainer = Passthrough
export const ChartTooltip = Passthrough
export const ChartTooltipContent = Passthrough
export const ChartLegend = Passthrough
export const ChartLegendContent = Passthrough
export const ChartStyle = Passthrough
export default Passthrough
