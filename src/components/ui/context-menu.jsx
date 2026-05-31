import * as React from "react"

// Placeholder for an unused shadcn/ui component.
// The canonical implementation depends on the npm package: @radix-ui/react-context-menu
// which is NOT installed in this project. To use this component for real:
//   1) npm install @radix-ui/react-context-menu
//   2) replace this file with the official shadcn/ui source for it.
// This passthrough keeps imports valid and the build green in the meantime.
const Passthrough = React.forwardRef(({ children }, ref) => React.createElement(React.Fragment, null, children))
Passthrough.displayName = "ShadcnPlaceholder"
export const ContextMenu = Passthrough
export const ContextMenuTrigger = Passthrough
export const ContextMenuContent = Passthrough
export const ContextMenuItem = Passthrough
export const ContextMenuCheckboxItem = Passthrough
export const ContextMenuRadioItem = Passthrough
export const ContextMenuLabel = Passthrough
export const ContextMenuSeparator = Passthrough
export const ContextMenuShortcut = Passthrough
export const ContextMenuGroup = Passthrough
export const ContextMenuPortal = Passthrough
export const ContextMenuSub = Passthrough
export const ContextMenuSubContent = Passthrough
export const ContextMenuSubTrigger = Passthrough
export const ContextMenuRadioGroup = Passthrough
export default Passthrough
