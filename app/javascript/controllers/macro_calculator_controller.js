import { Controller } from "@hotwired/stimulus"

// Confirm-your-targets screen (preferences/create). Two ways to edit:
//  - Change a gram field -> kcal (protein*4 + carbs*4 + fat*9) is
//    recalculated, and all three % fields are re-derived from that new
//    kcal (so they always sum to 100% in this mode).
//  - Change a % field directly -> kcal stays fixed at its last known value,
//    and only that macro's grams are recalculated from
//    (pct/100 * kcal) / rate. The other % fields are left alone, so typing
//    e.g. 20% into all three shows a running total (20, 40, 60%) instead of
//    silently renormalizing — that total is the feedback signal for
//    over/under-allocating calories.
export default class extends Controller {
  static targets = ["protein", "carbs", "fat", "kcal", "proteinPct", "carbsPct", "fatPct", "totalPct"]

  connect() {
    this.targetKcal = this.computeKcalFromGrams()
    this.kcalTarget.textContent = this.targetKcal
    this.syncPercentagesFromGrams()
    this.updateTotalPct()
  }

  recalculateFromGrams() {
    this.targetKcal = this.computeKcalFromGrams()
    this.kcalTarget.textContent = this.targetKcal
    this.syncPercentagesFromGrams()
    this.updateTotalPct()
  }

  recalculateFromPercent(event) {
    const field = event.currentTarget
    const macro = field.dataset.macro
    const rate = macro === "fat" ? 9 : 4
    const pct = parseFloat(field.value) || 0
    const grams = this.targetKcal > 0 ? Math.round((pct / 100) * this.targetKcal / rate) : 0

    this[`${macro}Target`].value = grams
    this.updateTotalPct()
  }

  computeKcalFromGrams() {
    const protein = parseFloat(this.proteinTarget.value) || 0
    const carbs = parseFloat(this.carbsTarget.value) || 0
    const fat = parseFloat(this.fatTarget.value) || 0
    return Math.round(protein * 4 + carbs * 4 + fat * 9)
  }

  syncPercentagesFromGrams() {
    const protein = parseFloat(this.proteinTarget.value) || 0
    const carbs = parseFloat(this.carbsTarget.value) || 0
    const fat = parseFloat(this.fatTarget.value) || 0
    const kcal = this.targetKcal
    const pct = (part) => (kcal > 0 ? Math.round((part / kcal) * 100) : 0)

    this.proteinPctTarget.value = pct(protein * 4)
    this.carbsPctTarget.value = pct(carbs * 4)
    this.fatPctTarget.value = pct(fat * 9)
  }

  updateTotalPct() {
    const total = (parseFloat(this.proteinPctTarget.value) || 0)
      + (parseFloat(this.carbsPctTarget.value) || 0)
      + (parseFloat(this.fatPctTarget.value) || 0)

    this.totalPctTarget.textContent = `${total}%`
    this.totalPctTarget.classList.toggle("text-danger", total !== 100)
  }
}
