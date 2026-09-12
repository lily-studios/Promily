--!strict

-- groups Promily promises under one explicit cancellation and cleanup owner

local module = {}

--————————————————————————————————————————————————————————————————————--

local core = script.Parent
local cancellation = require(core:WaitForChild("cancellation"))
local promiseModule = require(core:WaitForChild("promise"))

--————————————————————————————————————————————————————————————————————--

export type scope = {
	cancel: (reason: any?) -> boolean,
	delete: () -> boolean,
	getCount: () -> number,
	getToken: () -> promiseModule.cancellationToken,
	isCancelled: () -> boolean,
	isDeleted: () -> boolean,
	newPromise: <T>(
		executor: (
			resolve: (value: T | promiseModule.promise<T>) -> (),
			reject: (reason: any) -> (),
			onCancel: (callback: (reason: any?) -> ()) -> boolean
		) -> ()
	) -> promiseModule.promise<T>,
	track: <T>(promiseValue: promiseModule.promise<T>) -> promiseModule.promise<T>,
}

--————————————————————————————————————————————————————————————————————--

function module.new(): scope
	local cancellationSource = cancellation.new()
	local isDeleted = false
	local tracked: {[any]: promiseModule.observer<any>} = {}

	local function untrack(promiseValue: any)
		local observerValue = tracked[promiseValue]
		if not observerValue then return end

		tracked[promiseValue] = nil
		observerValue.disconnect()
	end

	local function track<T>(promiseValue: promiseModule.promise<T>): promiseModule.promise<T>
		assert(not isDeleted, "Promily scope is deleted.")

		if cancellationSource.isCancelled() then
			promiseValue.cancel(cancellationSource.getToken().getReason())
			return promiseValue
		end

		if tracked[promiseValue] then return promiseValue end

		local observerValue = promiseValue.observeSettled(function()
			untrack(promiseValue)
		end)

		tracked[promiseValue] = observerValue :: promiseModule.observer<any>

		return promiseValue
	end

	local function newPromise<T>(
		executor: (
			resolve: (value: T | promiseModule.promise<T>) -> (),
			reject: (reason: any) -> (),
			onCancel: (callback: (reason: any?) -> ()) -> boolean
		) -> ()
	): promiseModule.promise<T>
		local promiseValue = promiseModule.new(executor, cancellationSource.getToken())

		return track(promiseValue)
	end

	local function cancel(reason: any?): boolean
		if isDeleted then return false end

		local didCancel = cancellationSource.cancel(reason)

		for promiseValue, observerValue in tracked do
			observerValue.disconnect()
			promiseValue.cancel(reason)
		end

		table.clear(tracked)

		return didCancel
	end

	local function delete(): boolean
		if isDeleted then return false end

		cancel("Promily scope deleted.")
		isDeleted = true
		cancellationSource.delete()
		table.clear(tracked)

		return true
	end

	local function getCount(): number
		local count = 0

		for _ in tracked do
			count += 1
		end

		return count
	end

	local function getToken(): promiseModule.cancellationToken
		return cancellationSource.getToken()
	end

	local function isCancelled(): boolean
		return cancellationSource.isCancelled()
	end

	local function scopeIsDeleted(): boolean
		return isDeleted
	end

	return {
		cancel = cancel,
		delete = delete,
		getCount = getCount,
		getToken = getToken,
		isCancelled = isCancelled,
		isDeleted = scopeIsDeleted,
		newPromise = newPromise,
		track = track,
	}
end

--————————————————————————————————————————————————————————————————————--

return module
