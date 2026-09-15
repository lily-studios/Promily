--!strict

-- defines structured Promily error values shared across combinators and concurrency primitives

local module = {}

--————————————————————————————————————————————————————————————————————--

export type aggregateError = {
	kind: "AggregateError",
	reasons: {any},
}

export type cancelledAttemptError = {
	kind: "CancelledAttempt",
	reason: any?,
}

export type cancelledInputError = {
	kind: "CancelledInput",
	reason: any?,
}

export type cancelledMapperError = {
	kind: "CancelledMapper",
	reason: any?,
}

export type insufficientInputsError = {
	kind: "InsufficientInputs",
	requested: number,
	total: number,
}

export type queueClosedError = {
	kind: "QueueClosed",
}

export type queueDeletedError = {
	kind: "QueueDeleted",
	reason: any?,
}

export type queueFullError = {
	kind: "QueueFull",
	maxPending: number,
}

export type semaphoreDeletedError = {
	kind: "SemaphoreDeleted",
	reason: any?,
}

export type singleFlightDeletedError = {
	kind: "SingleFlightDeleted",
	reason: any?,
}

--————————————————————————————————————————————————————————————————————--

--- Creates a structured AggregateError.
---@param reasons {any} Input failure reasons.
---@return aggregateError errorValue Aggregate error.
function module.aggregate(reasons: {any}): aggregateError
	return {
		kind = "AggregateError",
		reasons = reasons,
	}
end

--————————————————————————————————————————————————————————————————————--

--- Creates a structured cancelled-attempt error.
---@param reason any? Cancellation reason.
---@return cancelledAttemptError errorValue Cancelled-attempt error.
function module.cancelledAttempt(reason: any?): cancelledAttemptError
	return {
		kind = "CancelledAttempt",
		reason = reason,
	}
end

--————————————————————————————————————————————————————————————————————--

--- Creates a structured cancelled-input error.
---@param reason any? Cancellation reason.
---@return cancelledInputError errorValue Cancelled-input error.
function module.cancelledInput(reason: any?): cancelledInputError
	return {
		kind = "CancelledInput",
		reason = reason,
	}
end

--————————————————————————————————————————————————————————————————————--

--- Creates a structured cancelled-mapper error.
---@param reason any? Cancellation reason.
---@return cancelledMapperError errorValue Cancelled-mapper error.
function module.cancelledMapper(reason: any?): cancelledMapperError
	return {
		kind = "CancelledMapper",
		reason = reason,
	}
end

--————————————————————————————————————————————————————————————————————--

--- Creates an error describing an impossible requested success count.
---@param requested number Requested number of successful inputs.
---@param total number Total available inputs.
---@return insufficientInputsError errorValue Insufficient-inputs error.
function module.insufficientInputs(requested: number, total: number): insufficientInputsError
	return {
		kind = "InsufficientInputs",
		requested = requested,
		total = total,
	}
end

--————————————————————————————————————————————————————————————————————--

--- Creates the error returned when work is submitted to a closed queue.
---@return queueClosedError errorValue Queue-closed error.
function module.queueClosed(): queueClosedError
	return {
		kind = "QueueClosed",
	}
end

--————————————————————————————————————————————————————————————————————--

--- Creates the error returned when a queue is deleted.
---@param reason any? Deletion reason.
---@return queueDeletedError errorValue Queue-deleted error.
function module.queueDeleted(reason: any?): queueDeletedError
	return {
		kind = "QueueDeleted",
		reason = reason,
	}
end

--————————————————————————————————————————————————————————————————————--

--- Creates the error returned when a queue has reached its pending capacity.
---@param maxPending number Configured pending capacity.
---@return queueFullError errorValue Queue-full error.
function module.queueFull(maxPending: number): queueFullError
	return {
		kind = "QueueFull",
		maxPending = maxPending,
	}
end

--————————————————————————————————————————————————————————————————————--

--- Creates the error returned when a semaphore is deleted.
---@param reason any? Deletion reason.
---@return semaphoreDeletedError errorValue Semaphore-deleted error.
function module.semaphoreDeleted(reason: any?): semaphoreDeletedError
	return {
		kind = "SemaphoreDeleted",
		reason = reason,
	}
end

--————————————————————————————————————————————————————————————————————--

--- Creates the error returned when a single-flight group is deleted.
---@param reason any? Deletion reason.
---@return singleFlightDeletedError errorValue Single-flight-deleted error.
function module.singleFlightDeleted(reason: any?): singleFlightDeletedError
	return {
		kind = "SingleFlightDeleted",
		reason = reason,
	}
end

--————————————————————————————————————————————————————————————————————--

return module
