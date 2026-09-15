--!strict

-- deduplicates concurrent work by key while isolating each consumer's cancellation

local module = {}

--————————————————————————————————————————————————————————————————————--

local core = script.Parent.Parent:WaitForChild("core")
local errors = require(core:WaitForChild("errors"))
local promiseModule = require(core:WaitForChild("promise"))

--————————————————————————————————————————————————————————————————————--

export type singleFlightKey = string | number

export type singleFlight = {
	clear: (reason: any?) -> number,
	delete: (reason: any?) -> boolean,
	getCount: () -> number,
	has: (key: singleFlightKey) -> boolean,
	isDeleted: () -> boolean,
	run: <T>(key: singleFlightKey, callback: () -> T | promiseModule.promise<T>) -> promiseModule.promise<T>,
}

type entry = {
	promiseValue: promiseModule.promise<any>,
}

--————————————————————————————————————————————————————————————————————--

--- Creates a keyed single-flight group for deduplicating concurrent work.
---@return singleFlight singleFlightValue New single-flight group.
function module.new(): singleFlight
	local entries: {[singleFlightKey]: entry} = {}
	local isDeletedValue = false

	local function createConsumer<T>(source: promiseModule.promise<T>): promiseModule.promise<T>
		return source.fork()
	end

	local function run<T>(
		key: singleFlightKey,
		callback: () -> T | promiseModule.promise<T>
	): promiseModule.promise<T>
		if isDeletedValue then
			return promiseModule.reject(errors.singleFlightDeleted("Promily single-flight group is deleted."))
		end

		local existing = entries[key]

		if existing then
			return createConsumer(existing.promiseValue :: promiseModule.promise<T>)
		end

		local source = promiseModule.try(callback)
		local entryValue: entry = {
			promiseValue = source :: promiseModule.promise<any>,
		}

		entries[key] = entryValue

		source.observeSettled(function()
			if entries[key] ~= entryValue then return end

			entries[key] = nil
		end)

		return createConsumer(source)
	end

	local function clear(reason: any?): number
		local count = 0
		local currentEntries = entries
		entries = {}

		for _, entryValue in currentEntries do
			count += 1
			entryValue.promiseValue.cancel(reason)
		end

		table.clear(currentEntries)

		return count
	end

	local function delete(reason: any?): boolean
		if isDeletedValue then return false end

		isDeletedValue = true
		clear(errors.singleFlightDeleted(reason))

		return true
	end

	local function getCount(): number
		local count = 0

		for _ in entries do
			count += 1
		end

		return count
	end

	local function has(key: singleFlightKey): boolean
		return entries[key] ~= nil
	end

	local function isDeleted(): boolean
		return isDeletedValue
	end

	return {
		clear = clear,
		delete = delete,
		getCount = getCount,
		has = has,
		isDeleted = isDeleted,
		run = run,
	}
end

--————————————————————————————————————————————————————————————————————--

return module
