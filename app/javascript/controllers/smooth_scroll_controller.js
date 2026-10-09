import { Controller } from "@hotwired/stimulus"

// Glides to the link's in-page target instead of jumping, and moves keyboard
// focus there. Without JavaScript the plain #anchor link still works.
export default class extends Controller {
  scroll(event) {
    const target = document.querySelector(this.element.hash)
    if (!target) return

    event.preventDefault()

    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    target.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth" })
    target.focus({ preventScroll: true })
  }
}
