import * as React from "react"

// Placeholder for an unused shadcn/ui component.
// The canonical implementation depends on the npm package: embla-carousel-react
// which is NOT installed in this project. To use this component for real:
//   1) npm install embla-carousel-react
//   2) replace this file with the official shadcn/ui source for it.
// This passthrough keeps imports valid and the build green in the meantime.
const Passthrough = React.forwardRef(({ children }, ref) => React.createElement(React.Fragment, null, children))
Passthrough.displayName = "ShadcnPlaceholder"
export const Carousel = Passthrough
export const CarouselContent = Passthrough
export const CarouselItem = Passthrough
export const CarouselPrevious = Passthrough
export const CarouselNext = Passthrough
export default Passthrough
