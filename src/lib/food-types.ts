export interface FoodCandidate {
  id:                string
  name:              string
  brand:             string | null
  calories_per_100g: number | null
  protein_per_100g:  number | null
  fat_per_100g:      number | null
  carbs_per_100g:    number | null
  source:            'local' | 'fatsecret'
}

export interface RawFoodEntry {
  food_name: string
  amount:    number
  unit:      string
  calories:  number | null
  protein:   number | null
  fat:       number | null
  carbs:     number | null
}
