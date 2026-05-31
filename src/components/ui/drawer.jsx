import * as React from "react"

// Placeholder for an unused shadcn/ui component.
// The canonical implementation depends on the npm package: vaul
// which is NOT installed in this project. To use this component for real:
//   1) npm install vaul
//   2) replace this file with the official shadcn/ui source for it.
// This passthrough keeps imports valid and the build green in the meantime.
const Passthrough = React.forwardRef(({ children }, ref) => React.createElement(React.Fragment, null, children))
Passthrough.displayName = "ShadcnPlaceholder"
export const Drawer = Passthrough
export const DrawerPortal = Passthrough
export const DrawerOverlay = Passthrough
export const DrawerTrigger = Passthrough
export const DrawerClose = Passthrough
export const DrawerContent = Passthrough
export const DrawerHeader = Passthrough
export const DrawerFooter = Passthrough
export const DrawerTitle = Passthrough
export const DrawerDescription = Passthrough
export default Passthrough
