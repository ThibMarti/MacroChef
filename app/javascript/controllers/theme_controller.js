import { Controller } from "@hotwired/stimulus"

// Toggles data-theme on <html> between "light" and "dark", persists the
// choice in localStorage, and keeps the toggle's active segment in sync.
// The very first paint (before Stimulus connects) is handled by an inline
// script in the layout head to avoid a flash of the wrong theme.
export default class extends Controller {
  static targets = ["option"]

  connect() {
    this.applyActiveState(this.currentTheme())
  }

  set(event) {
    const theme = event.params.mode

    document.documentElement.setAttribute("data-theme", theme)
    localStorage.setItem("macrochef-theme", theme)
    this.applyActiveState(theme)
  }

  currentTheme() {
    // The inline script in the layout head always sets this before Stimulus
    // connects (light by default unless the user toggled dark before).
    return document.documentElement.getAttribute("data-theme") || "light"
  }

  applyActiveState(theme) {
    this.optionTargets.forEach((option) => {
      option.classList.toggle("active", option.dataset.themeModeParam === theme)
    })
  }
}
