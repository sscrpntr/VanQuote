import { Controller } from "@hotwired/stimulus"

// Publishes the sticky header's real height as --landing-header-offset, so the
// landing sections and scroll snapping line up below it in every language and
// at every width. The values in application.css are only first-paint fallbacks.
export default class extends Controller {
  connect() {
    this.observer = new ResizeObserver(([entry]) => {
      const height = Math.ceil(entry.borderBoxSize[0].blockSize)
      document.documentElement.style.setProperty("--landing-header-offset", `${height}px`)
    })
    this.observer.observe(this.element)
  }

  // Turbo keeps <html> across visits, so the inline value must not leak to other pages.
  disconnect() {
    this.observer.disconnect()
    document.documentElement.style.removeProperty("--landing-header-offset")
  }
}
