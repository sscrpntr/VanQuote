import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["error", "form", "token"]

  connect() {
    const token = window.location.hash.slice(1)
    window.history.replaceState(null, document.title, window.location.pathname)

    if (!token || token.length > 2048) {
      this.errorTarget.hidden = false
      return
    }

    this.tokenTarget.value = token
    this.formTarget.requestSubmit()
  }
}
