import * as React from "react"

// Placeholder for an unused shadcn/ui component.
// The canonical implementation depends on the npm package: @radix-ui/react-menubar
// which is NOT installed in this project. To use this component for real:
//   1) npm install @radix-ui/react-menubar
//   2) replace this file with the official shadcn/ui source for it.
// This passthrough keeps imports valid and the build green in the meantime.
const Passthrough = React.forwardRef(({ children }, ref) => React.createElement(React.Fragment, null, children))
Passthrough.displayName = "ShadcnPlaceholder"
export const Menubar = Passthrough
export const MenubarMenu = Passthrough
export const MenubarTrigger = Passthrough
export const MenubarContent = Passthrough
export const MenubarItem = Passthrough
export const MenubarSeparator = Passthrough
export const MenubarLabel = Passthrough
export const MenubarCheckboxItem = Passthrough
export const MenubarRadioGroup = Passthrough
export const MenubarRadioItem = Passthrough
export const MenubarPortal = Passthrough
export const MenubarSubContent = Passthrough
export const MenubarSubTrigger = Passthrough
export const MenubarGroup = Passthrough
export const MenubarSub = Passthrough
export const MenubarShortcut = Passthrough
export default Passthrough
