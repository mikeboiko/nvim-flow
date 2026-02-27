local template = require("nvim-flow.template")

describe("nvim-flow template", function()
  it("expands known template variables", function()
    local out = template.expand("{{filepath}}|{{dir}}|{{filename}}|{{ext}}|{{repo}}|{{folder}}", {
      filepath = "/tmp/a/test.py",
      dir = "/tmp/a",
      filename = "test",
      ext = "py",
      repo = "my-repo",
      folder = "a",
    })

    assert.are.equal("/tmp/a/test.py|/tmp/a|test|py|my-repo|a", out)
  end)
end)
