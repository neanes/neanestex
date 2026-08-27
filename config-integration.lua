testfiledir = "tests/latex/integration"
testsuppdir = testfiledir .. "/fixtures"

-- The integration tests render the project examples directly.
table.insert(checkexamplefiles, "funeral-service-blameless.byztex")
table.insert(checkexamplefiles, "olihc-1.byztex")
