-- One source for the entity footprint, recipe and runtime coverage.
return {
    {name = "the-cave-roof-support-small", size = 2, width = 2, height = 2, rotatable = false,
        area = 10, plates = 50, seconds = 10,
        technology = "the-cave-roof-support", research_count = 300,
        science = {"automation-science-pack", "logistic-science-pack"}},
    {name = "the-cave-roof-support-medium", size = 3, width = 2, height = 3, rotatable = true,
        area = 20, plates = 100, seconds = 20,
        technology = "the-cave-roof-support-2", research_count = 500,
        science = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack"}},
    {name = "the-cave-roof-support-large", size = 4, width = 2, height = 4, rotatable = true,
        area = 30, plates = 200, seconds = 30,
        technology = "the-cave-roof-support-3", research_count = 700,
        science = {"automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack", "production-science-pack"}},
}
