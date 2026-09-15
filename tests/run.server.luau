--!strict

-- runs Promily package tests without external test dependencies

local tests = require(script.Parent.spec)

--————————————————————————————————————————————————————————————————————--

local failures = 0
local passed = 0

local names: {string} = {}

--————————————————————————————————————————————————————————————————————--

for name in tests do
	names[#names + 1] = name
end

table.sort(names)

--————————————————————————————————————————————————————————————————————--

for _, name in names do
	local callback = tests[name]
	local success, failure = pcall(callback)

	if success then
		passed += 1
		print(`[Promily Test] PASS {name}`)
		continue
	end

	failures += 1
	warn(`[Promily Test] FAIL {name}: {tostring(failure)}`)
end

--————————————————————————————————————————————————————————————————————--

print(`[Promily Test] {passed} passed, {failures} failed.`)

assert(failures == 0, `[Promily Test] {failures} test(s) failed.`)
