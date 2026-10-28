// Shared by the meal-kit tests. Not a test file itself.

/// A trimmed weekly meal-kit PDF (story text replaced) as the on-device
/// extractor emits it: one table row per line with columns joined by spaces,
/// recipe columns split by tabs, and the page header atop every page.
const String kMenuKitText = '''
MEDITERRANEAN | FALL | OCTOBER 2ND, 2026
PATRAS, GREECE
A short story about the week's featured town.
MENU
MONDAY
PATRA BAKED GIGANTES BEAN PLAKI
ROASTED FENNEL WITH KALAMATA OLIVES
TUESDAY
PATRA BAKED COD AND ROASTED FENNEL
WARM GREEK LENTIL AND SPINACH SALAD
MEDITERRANEAN | FALL | OCTOBER 2ND, 2026
PATRAS, GREECE
A short story about the week's featured town.
VEGETARIAN MENU
MONDAY
PATRA BAKED GIGANTES BEAN PLAKI
ROASTED FENNEL WITH KALAMATA OLIVES
TUESDAY
PATRA BAKED HALLOUMI AND ROASTED FENNEL
WARM GREEK LENTIL AND SPINACH SALAD
MEDITERRANEAN | FALL | OCTOBER 2ND, 2026
SHOPPING LIST
RECIPE PRODUCE QTY NOTES EST.  COST
T, W Cherry tomatoes 1 pint Halve just before cooking \$3.50
M, T, W Fennel 4 medium bulbs Keep the fronds for garnish \$7.00
M, T, W, F Lemon 4 - \$2.00
F Pomegranate arils 1 package (4.4 oz) - \$3.50
RECIPE MEAT |  SEAFOOD QTY NOTES EST.  COST
T Cod fillets 12 oz (¾ lb) Ask for skinless, center-cut \$9.00
RECIPE DAIRY QTY NOTES EST.  COST
M, W, Th, F Feta cheese 12 ounces Block, crumble by hand \$7.00
RECIPE BAKERY |  MISC QTY NOTES EST.  COST
M, W Butter beans, canned 3 (15.5 oz ea) cans Stands in for gigantes beans \$4.50
F Phyllo dough 1 (1#) box, thawed Thaw overnight in the fridge \$4.00
PANTRY QTY PANTRY QTY
Canned chickpeas (Garbanzo) - Capers -
Canned tomatoes 1 (28 oz) can Sea salt As needed
Kalamata olives 1/3 cup plus 2 Tablespoons Red pepper flakes ½ teaspoon
Bay leaves 1
MEDITERRANEAN | FALL | OCTOBER 2ND, 2026
VEGETARIAN SHOPPING LIST
RECIPE PRODUCE QTY NOTES EST.  COST
T, W Cherry tomatoes 1 pint Halve just before cooking \$3.50
M, T, W Fennel 4 medium bulbs Keep the fronds for garnish \$7.00
M, T, W, F Lemon 4 - \$2.00
F Pomegranate arils 1 package (4.4 oz) - \$3.50
RECIPE DAIRY QTY NOTES EST.  COST
Th Eggs 12 large - \$4.00
M, W, Th, F Feta cheese 12 oz Block, crumble by hand \$7.00
T Halloumi 12 oz (¾ lb) Slice into planks \$8.00
RECIPE BAKERY |  MISC QTY NOTES EST.  COST
M, W Butter beans, canned 3 (15.5 oz ea) cans Stands in for gigantes beans \$4.50
F Phyllo dough 1 (1#) box, thawed Thaw overnight in the fridge \$4.00
PANTRY QTY PANTRY QTY
Canned chickpeas (Garbanzo) - Capers -
Canned tomatoes 1 (28 oz) can Sea salt As needed
Kalamata olives 1/3 cup plus 2 Tablespoons Red pepper flakes ½ teaspoon
Bay leaves 1
MEDITERRANEAN | FALL | OCTOBER 2ND, 2026
WEEKLY PREP GUIDE
USE THIS GUIDE TO PREP FOR THE ENTIRE WEEK
LEGUMES & GRAINS
Drain and rinse all 3 cans of butter beans Sunday.
MEDITERRANEAN | FALL | OCTOBER 2ND, 2026
PATRA BAKED COD AND ROASTED FENNEL
WARM GREEK LENTIL AND SPINACH SALAD
A short story about the dish.
TUESDAY PREP
Slice fennel thin and halve the cherry tomatoes
Serves: 4 | Prep Time: 10 minutes | Cook Time: 20 minutes | Active Time: 12 minutes
INGREDIENTS\tINSTRUCTIONS
1 medium fennel bulb, thinly sliced\t1. Heat oven to 400°F.
6 ounces cherry tomatoes, halved\t2. Toss fennel and tomatoes with 2 Tbsp olive oil in a
2 Tablespoons extra virgin olive oil\tbaking dish.
12 ounces cod fillets, skinless\t3. Roast 10 minutes.
1 lemon, thinly sliced, plus 1 lemon, juiced (about 2 7.Drizzle with lemon juice. Serve
   Tablespoons)\twith focaccia.
\t8. Bake 10 more minutes.
COMMON SUBSTITUTIONS
This dish is dairy-free and gluten-free.
PATRA BAKED COD AND ROASTED FENNEL Nutritional Information (per serving):
Calories: 300 kcal | Protein: 24g | Carbs: 8g
VEGETARIAN | MEDITERRANEAN | FALL | OCTOBER 2ND, 2026
PATRA BAKED HALLOUMI AND ROASTED FENNEL
WARM GREEK LENTIL AND SPINACH SALAD
Serves: 4 | Prep Time: 10 minutes | Cook Time: 20 minutes | Active Time: 12 minutes
INGREDIENTS\tINSTRUCTIONS
12 ounces halloumi, sliced into ½-inch planks\t1. Heat oven to 400°F.
1 medium fennel bulb, thinly sliced
COMMON SUBSTITUTIONS
MEDITERRANEAN | FALL | OCTOBER 2ND, 2026
WARM GREEK LENTIL AND SPINACH SALAD
SIDE DISH
Serves: 4 | Prep Time: 5 minutes | Cook Time: 8 minutes | Active Time: 8 minutes
INGREDIENTS\tINSTRUCTIONS
12 ounces boneless, skinless chicken thighs, cut into 1½-\t1.Warm 1 Tbsp olive oil.
pieces, cook to 165°F internal\t2.Add lentils and warm through.
4 ounces baby spinach\t3.Stir in spinach.
COMMON SUBSTITUTIONS
MEDITERRANEAN | FALL | PATRAS, GREECE
WINE IN PATRAS
A short note about the local wine.
''';
