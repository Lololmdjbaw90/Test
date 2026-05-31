import * as React from "react"

// Placeholder for an unused shadcn/ui component.
// The canonical implementation depends on the npm package: @radix-ui/react-collapsible
// which is NOT installed in this project. To use this component for real:
//   1) npm install @radix-ui/react-collapsible
//   2) replace this file with the official shadcn/ui source for it.
// This passthrough keeps imports valid and the build green in the meantime.
const Passthrough = React.forwardRef(({ children }, ref) => React.createElement(React.Fragment, null, children))
Passthrough.displayName = "ShadcnPlaceholder"
export const Collapsible = Passthrough
export const CollapsibleTrigger = Passthrough
export const CollapsibleContent = Passthrough
export default Passthrough
