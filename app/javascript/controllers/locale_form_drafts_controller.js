import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.activeForm = null
    this.rememberActiveForm = this.rememberActiveForm.bind(this)
    this.attachDraft = this.attachDraft.bind(this)

    document.addEventListener("focusin", this.rememberActiveForm)
    document.addEventListener("input", this.rememberActiveForm)
    document.addEventListener("change", this.rememberActiveForm)
    document.addEventListener("submit", this.attachDraft, true)
  }

  disconnect() {
    document.removeEventListener("focusin", this.rememberActiveForm)
    document.removeEventListener("input", this.rememberActiveForm)
    document.removeEventListener("change", this.rememberActiveForm)
    document.removeEventListener("submit", this.attachDraft, true)
  }

  rememberActiveForm(event) {
    const form = event.target.closest("form[data-locale-draft]")
    if (form) this.activeForm = form
  }

  attachDraft(event) {
    const languageForm = event.target
    if (!languageForm.matches(".language-selector-form")) return

    const sourceForm = this.activeForm || Array.from(document.querySelectorAll("form[data-locale-draft]"))
      .find((form) => Array.from(form.elements).some((field) => field.value))
    if (!sourceForm?.isConnected) return

    const values = {}
    for (const field of sourceForm.elements) {
      if (!field.name || field.disabled || ["password", "submit", "button", "file", "reset"].includes(field.type)) continue
      if (["authenticity_token", "_method"].includes(field.name)) continue

      values[field.name] = field.type === "checkbox" ? field.checked : field.value
    }

    let payload = languageForm.querySelector("input[name='locale_form_draft']")
    if (!payload) {
      payload = document.createElement("input")
      payload.type = "hidden"
      payload.name = "locale_form_draft"
      languageForm.append(payload)
    }
    payload.value = JSON.stringify({
      form_key: sourceForm.dataset.localeDraft,
      values
    })
  }
}
