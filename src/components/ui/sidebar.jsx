import * as React from "react"

// Placeholder for an unused shadcn/ui component.
// The canonical implementation depends on the npm package: (large component; uses installed deps but omitted from export)
// which is NOT installed in this project. To use this component for real:
//   1) npm install (large component; uses installed deps but omitted from export)
//   2) replace this file with the official shadcn/ui source for it.
// This passthrough keeps imports valid and the build green in the meantime.
const Passthrough = React.forwardRef(({ children }, ref) => React.createElement(React.Fragment, null, children))
Passthrough.displayName = "ShadcnPlaceholder"
export const Sidebar = Passthrough
export const SidebarProvider = Passthrough
export const SidebarTrigger = Passthrough
export const SidebarContent = Passthrough
export const SidebarHeader = Passthrough
export const SidebarFooter = Passthrough
export const SidebarMenu = Passthrough
export const SidebarMenuItem = Passthrough
export const SidebarMenuButton = Passthrough
export const SidebarGroup = Passthrough
export const SidebarInset = Passthrough
export const useSidebar = Passthrough
export default Passthrough
