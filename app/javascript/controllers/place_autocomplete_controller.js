import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    apiKey: String
  }

  static targets = [
    "originInput",
    "destinationInput"
  ]

  async connect() {
    try {
      await this.loadGoogleMaps()

      const { PlaceAutocompleteElement } =
        await window.google.maps.importLibrary("places")

      this.createAutocomplete(
        this.originInputTarget,
        PlaceAutocompleteElement
      )

      this.createAutocomplete(
        this.destinationInputTarget,
        PlaceAutocompleteElement
      )
    } catch (error) {
      console.error("Google Places error:", error)
    }
  }

  createAutocomplete(inputTarget, PlaceAutocompleteElement) {
    const autocomplete = new PlaceAutocompleteElement()

    autocomplete.placeholder = inputTarget.placeholder || ""

    const wrapper = inputTarget.parentElement

    inputTarget.type = "hidden"

    wrapper.insertBefore(autocomplete, inputTarget)

    autocomplete.addEventListener(
      "gmp-select",
      async ({ placePrediction }) => {
        const place = placePrediction.toPlace()

        await place.fetchFields({
          fields: ["formattedAddress"]
        })

        inputTarget.value = place.formattedAddress || ""

        inputTarget.dispatchEvent(
          new Event("change", { bubbles: true })
        )
      }
    )

    return autocomplete
  }

  async loadGoogleMaps() {
    if (window.google?.maps?.importLibrary) {
      return
    }

    if (window.vanQuoteGoogleMapsReady) {
      await window.vanQuoteGoogleMapsReady
      return
    }

    window.vanQuoteGoogleMapsReady =
      new Promise((resolve, reject) => {
        const existingScript = document.querySelector(
          'script[data-vanquote-google-maps="true"]'
        )

        if (existingScript) {
          existingScript.addEventListener(
            "load",
            resolve,
            { once: true }
          )

          existingScript.addEventListener(
            "error",
            reject,
            { once: true }
          )

          return
        }

        window.vanQuoteGoogleMapsCallback = () => {
          resolve()
        }

        const script = document.createElement("script")

        script.src =
          "https://maps.googleapis.com/maps/api/js" +
          `?key=${encodeURIComponent(this.apiKeyValue)}` +
          "&loading=async" +
          "&libraries=places" +
          "&callback=vanQuoteGoogleMapsCallback"

        script.async = true
        script.defer = true
        script.dataset.vanquoteGoogleMaps = "true"

        script.onerror = () => {
          reject(
            new Error(
              "No se ha podido cargar Google Maps."
            )
          )
        }

        document.head.appendChild(script)
      })

    await window.vanQuoteGoogleMapsReady
  }
}
