local lock = require("nvim-flow.lock")

describe("nvim-flow lock", function()
	before_each(function()
		lock.clear()
	end)

	it("sets and clears lock state", function()
		lock.set("/tmp/a.py")
		assert.are.equal("/tmp/a.py", lock.get())

		lock.clear()
		assert.is_nil(lock.get())
	end)
end)
