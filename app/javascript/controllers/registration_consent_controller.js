import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["terms", "communications", "submit"]
  static values = { requireCommunications: Boolean }

  connect() {
    this.update()
  }

  update() {
    const termsAccepted = !this.hasTermsTarget || this.termsTarget.checked
    const communicationsAccepted = !this.requireCommunicationsValue ||
      (this.hasCommunicationsTarget && this.communicationsTarget.checked)

    this.submitTarget.disabled = !(termsAccepted && communicationsAccepted)
  }
}
