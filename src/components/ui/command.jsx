import * as React from "react"

// Placeholder for an unused shadcn/ui component.
// The canonical implementation depends on the npm package: cmdk
// which is NOT installed in this project. To use this component for real:
//   1) npm install cmdk
//   2) replace this file with the official shadcn/ui source for it.
// This passthrough keeps imports valid and the build green in the meantime.
const Passthrough = React.forwardRef(({ children }, ref) => React.createElement(React.Fragment, null, children))
Passthrough.displayName = "ShadcnPlaceholder"
export const Command = Passthrough
export const CommandDialog = Passthrough
export const CommandInput = Passthrough
export const CommandList = Passthrough
export const CommandEmpty = Passthrough
export const CommandGroup = Passthrough
export const CommandItem = Passthrough
export const CommandShortcut = Passthrough
export const CommandSeparator = Passthrough
export default Passthrough
