--!strict

-- owns cancellation sources and read-only cancellation tokens

local module = {}

--————————————————————————————————————————————————————————————————————--

export type connection = {
	connected: boolean,
	disconnect: () -> boolean,
}

export type token = {
	getReason: () -> any?,
	isCancelled: () -> boolean,
	onCancelled: (callback: (reason: any?) -> ()) -> connection,
	throwIfCancelled: (message: string?) -> (),
}

export type source = {
	cancel: (reason: any?) -> boolean,
	delete: () -> boolean,
	getToken: () -> token,
	isCancelled: () -> boolean,
	isDeleted: () -> boolean,
}

type listener = {
	callback: (reason: any?) -> (),
	connected: boolean,
	connectionValue: connection?,
}

--————————————————————————————————————————————————————————————————————--

function module.new(): source
	local isCancelled = false
	local isDeleted = false
	local listeners: {listener} = {}
	local reason: any? = nil

	local function disconnectListener(listenerValue: listener): boolean
		if not listenerValue.connected then return false end

		listenerValue.connected = false

		local connectionValue = listenerValue.connectionValue

		if connectionValue then
			connectionValue.connected = false
		end

		local index = table.find(listeners, listenerValue)

		if index then
			table.remove(listeners, index)
		end

		return true
	end

	local function onCancelled(callback: (reason: any?) -> ()): connection
		assert(not isDeleted, "Promily cancellation source is deleted.")

		if isCancelled then
			task.defer(callback, reason)

			return {
				connected = false,
				disconnect = function(): boolean
					return false
				end,
			}
		end

		local listenerValue: listener = {
			callback = callback,
			connected = true,
			connectionValue = nil,
		}

		local connectionValue: connection = {
			connected = true,

			disconnect = function(): boolean
				return disconnectListener(listenerValue)
			end,
		}

		listenerValue.connectionValue = connectionValue
		listeners[#listeners + 1] = listenerValue

		return connectionValue
	end

	local function getReason(): any?
		return reason
	end

	local function tokenIsCancelled(): boolean
		return isCancelled
	end

	local function throwIfCancelled(message: string?)
		if not isCancelled then return end

		local errorMessage = message

		if errorMessage == nil then
			errorMessage = "Promily operation was cancelled."
		end

		error(errorMessage, 2)
	end

	local tokenValue: token = {
		getReason = getReason,
		isCancelled = tokenIsCancelled,
		onCancelled = onCancelled,
		throwIfCancelled = throwIfCancelled,
	}

	local function cancel(cancelReason: any?): boolean
		if isDeleted then return false end
		if isCancelled then return false end

		isCancelled = true
		reason = cancelReason

		local currentListeners = listeners
		listeners = {}

		for _, listenerValue in currentListeners do
			if not listenerValue.connected then continue end

			listenerValue.connected = false

			local connectionValue = listenerValue.connectionValue

			if connectionValue then
				connectionValue.connected = false
			end

			task.defer(listenerValue.callback, cancelReason)
		end

		table.clear(currentListeners)

		return true
	end

	local function delete(): boolean
		if isDeleted then return false end

		isDeleted = true

		for _, listenerValue in listeners do
			listenerValue.connected = false

			local connectionValue = listenerValue.connectionValue

			if connectionValue then
				connectionValue.connected = false
			end
		end

		table.clear(listeners)

		return true
	end

	local function getToken(): token
		return tokenValue
	end

	local function sourceIsCancelled(): boolean
		return isCancelled
	end

	local function sourceIsDeleted(): boolean
		return isDeleted
	end

	return {
		cancel = cancel,
		delete = delete,
		getToken = getToken,
		isCancelled = sourceIsCancelled,
		isDeleted = sourceIsDeleted,
	}
end

--————————————————————————————————————————————————————————————————————--

return module
