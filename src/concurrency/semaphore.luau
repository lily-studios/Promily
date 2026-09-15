--!strict

-- limits simultaneous access to a shared asynchronous resource without polling

local module = {}

--————————————————————————————————————————————————————————————————————--

local core = script.Parent.Parent:WaitForChild("core")

local errors = require(core:WaitForChild("errors"))
local promiseModule = require(core:WaitForChild("promise"))

--————————————————————————————————————————————————————————————————————--

export type permit = {
	isReleased: () -> boolean,
	release: () -> boolean,
}

export type semaphore = {
	acquire: () -> promiseModule.promise<permit>,
	delete: (reason: any?) -> boolean,
	getActiveCount: () -> number,
	getAvailableCount: () -> number,
	getPendingCount: () -> number,
	isDeleted: () -> boolean,
	tryAcquire: () -> permit?,
	use: <T>(callback: () -> T | promiseModule.promise<T>) -> promiseModule.promise<T>,
}

type waiter = {
	deferredValue: promiseModule.deferred<permit>,
}

--————————————————————————————————————————————————————————————————————--

local function isPositiveInteger(value: number): boolean
	if value ~= value then
		return false
	end

	if value >= math.huge then
		return false
	end

	if value < 1 then
		return false
	end

	if value % 1 ~= 0 then
		return false
	end

	return true
end

--————————————————————————————————————————————————————————————————————--

--- Creates a semaphore that limits simultaneous asynchronous work.
---@param limit number Maximum simultaneous permits.
---@return semaphore semaphoreValue New semaphore.
function module.new(limit: number): semaphore
	assert(
		isPositiveInteger(limit),
		"Promily semaphore limit must be a positive integer."
	)

	local activeCount = 0
	local isDeletedValue = false
	local waiters: {waiter} = {}

	local createPermit: () -> permit
	local releaseSlot: () -> ()

	--————————————————————————————————————————————————————————————————————--

	local function grantNext()
		if isDeletedValue then
			return
		end

		if activeCount >= limit then
			return
		end

		local scanCount = #waiters

		for _ = 1, scanCount do
			if activeCount >= limit then
				break
			end

			local waiterValue = table.remove(waiters, 1)

			if not waiterValue then
				break
			end

			if waiterValue.deferredValue.promise.isSettled() then
				continue
			end

			activeCount += 1

			local permitValue = createPermit()
			waiterValue.deferredValue.resolve(permitValue)
		end
	end

	--————————————————————————————————————————————————————————————————————--

	releaseSlot = function()
		activeCount -= 1

		assert(
			activeCount >= 0,
			"Promily semaphore active count became negative."
		)

		grantNext()
	end

	--————————————————————————————————————————————————————————————————————--

	createPermit = function(): permit
		local released = false

		--- Releases this permit once.
		---@return boolean releasedValue Whether the permit was released.
		local function release(): boolean
			if released then
				return false
			end

			released = true
			releaseSlot()

			return true
		end

		--- Returns whether this permit has already been released.
		---@return boolean releasedValue Whether the permit is released.
		local function isReleased(): boolean
			return released
		end

		return {
			isReleased = isReleased,
			release = release,
		}
	end

	--————————————————————————————————————————————————————————————————————--

	--- Attempts to acquire a permit immediately without waiting.
	---@return permit? permitValue Permit when capacity is immediately available.
	local function tryAcquire(): permit?
		if isDeletedValue then
			return nil
		end

		if activeCount >= limit then
			return nil
		end

		if #waiters > 0 then
			return nil
		end

		activeCount += 1

		return createPermit()
	end

	--————————————————————————————————————————————————————————————————————--

	--- Acquires a permit when semaphore capacity becomes available.
	---@return promiseModule.promise<permit> promiseValue Permit Promise.
	local function acquire(): promiseModule.promise<permit>
		if isDeletedValue then
			return promiseModule.reject(
				errors.semaphoreDeleted("Promily semaphore is deleted.")
			)
		end

		local immediatePermit = tryAcquire()

		if immediatePermit then
			return promiseModule.resolve(immediatePermit)
		end

		local deferredValue: promiseModule.deferred<permit> = promiseModule.defer()

		local waiterValue: waiter = {
			deferredValue = deferredValue,
		}

		waiters[#waiters + 1] = waiterValue

		deferredValue.promise.onCancel(function()
			local index = table.find(waiters, waiterValue)

			if not index then
				return
			end

			table.remove(waiters, index)
		end)

		return deferredValue.promise
	end

	--————————————————————————————————————————————————————————————————————--

	--- Runs asynchronous work while holding one semaphore permit.
	---@generic T
	---@param callback fun(): T | promiseModule.promise<T> Work callback.
	---@return promiseModule.promise<T> promiseValue Work result Promise.
	local function use<T>(
		callback: () -> T | promiseModule.promise<T>
	): promiseModule.promise<T>
		local deferredValue: promiseModule.deferred<T> = promiseModule.defer()

		local acquirePromise = acquire()
		local workStarted = false

		acquirePromise.observe(
			function(permitValue: permit)
				if deferredValue.promise.isCancelled() then
					permitValue.release()

					return
				end

				workStarted = true

				local source: promiseModule.promise<T> = promiseModule.try(callback)

				source.observe(
					function(value: T)
						permitValue.release()
						deferredValue.resolve(value)
					end,

					function(reason: any)
						permitValue.release()
						deferredValue.reject(reason)
					end,

					function(reason: any?)
						permitValue.release()
						deferredValue.cancel(reason)
					end
				)
			end,

			function(reason: any)
				deferredValue.reject(reason)
			end,

			function(reason: any?)
				deferredValue.cancel(reason)
			end
		)

		deferredValue.promise.onCancel(function(reason: any?)
			if workStarted then
				return
			end

			acquirePromise.cancel(reason)
		end)

		return deferredValue.promise
	end

	--————————————————————————————————————————————————————————————————————--

	--- Deletes the semaphore and rejects all pending acquisitions.
	---@param reason any? Optional deletion reason.
	---@return boolean deletedValue Whether deletion occurred.
	local function delete(reason: any?): boolean
		if isDeletedValue then
			return false
		end

		isDeletedValue = true

		local currentWaiters = waiters
		waiters = {}

		local errorValue = errors.semaphoreDeleted(reason)

		for _, waiterValue in currentWaiters do
			waiterValue.deferredValue.reject(errorValue)
		end

		table.clear(currentWaiters)

		return true
	end

	--————————————————————————————————————————————————————————————————————--

	--- Returns the number of currently held permits.
	---@return number activeCountValue Active permit count.
	local function getActiveCount(): number
		return activeCount
	end

	--————————————————————————————————————————————————————————————————————--

	--- Returns the number of immediately available permits.
	---@return number availableCount Available permit count.
	local function getAvailableCount(): number
		return math.max(limit - activeCount, 0)
	end

	--————————————————————————————————————————————————————————————————————--

	--- Returns the number of callers waiting for a permit.
	---@return number pendingCount Pending acquisition count.
	local function getPendingCount(): number
		return #waiters
	end

	--————————————————————————————————————————————————————————————————————--

	--- Returns whether this semaphore has been deleted.
	---@return boolean deletedValue Whether the semaphore is deleted.
	local function isDeleted(): boolean
		return isDeletedValue
	end

	--————————————————————————————————————————————————————————————————————--

	return {
		acquire = acquire,
		delete = delete,
		getActiveCount = getActiveCount,
		getAvailableCount = getAvailableCount,
		getPendingCount = getPendingCount,
		isDeleted = isDeleted,
		tryAcquire = tryAcquire,
		use = use,
	}
end

--————————————————————————————————————————————————————————————————————--

return module
