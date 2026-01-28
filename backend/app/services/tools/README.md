# Tools System

Agent tools that execute actions and create visual cells in the iOS app.

## How It Works

1. **Agent calls tool** → LLM generates tool call with parameters
2. **Registry creates ThreadMessage** → Tool cell appears in iOS (status: `in_progress`) if user facing
3. **Tool executes** → Returns result data
4. **Registry updates ThreadMessage** → Tool cell updates (status: `success`/`failure`)

## ThreadMessage Metadata Structure

All tools use standardized `tool_activity` metadata:

```ruby
{
  tool_activity: {
    id: "unique-activity-id",           # Tool execution ID
    name: "create_task",                # Tool name
    status: "success",                  # in_progress | success | failure
    input: { title: "Do thing" },       # Tool parameters
    data: {                             # Tool-specific output (standardized location)
      task_id: 123,
      task_title: "Do thing",
      task_status: "active"
    },
    display_message: "Creating task",  # Optional UI message (cleared on completion)
    error: "Something failed"           # Error message if status is failure
  }
}
```

**Key Rules:**
- ALL tool output data goes in `data` field
- Use ThreadMessage instance methods to update metadata:
  - `message.update_tool_activity_data({ task_id: 123 })` - Updates `data` fields
  - `message.update_tool_activity({ status: 'success' })` - Updates top-level fields
  - `message.delete_tool_activity_fields([:display_message])` - Deletes fields

## Adding a New Tool

### 1. Create Tool Class

```ruby
# app/services/tools/system/my_tool.rb
module Tools
  module System
    class MyTool < BaseTool
      def self.metadata
        super.merge(
          name: 'my_tool',
          description: 'What this tool does',
          params_hint: 'param1 (required), param2 (optional)',
          is_user_facing: true  # Creates iOS cell
        )
      end

      def self.schema
        {
          type: 'object',
          properties: {
            param1: {
              type: 'string',
              description: 'Parameter description'
            }
          },
          required: ['param1'],
          additionalProperties: false
        }
      end

      def execute(param1:, param2: nil)
        # Do work here
        result = do_something(param1)

        # Return standardized result
        success(
          result_id: result.id,          # Goes in tool_activity.data
          result_title: result.title,
          display_message: "Created thing!"  # Optional
        )
      rescue => e
        error("Failed: #{e.message}")
      end
    end
  end
end
```

### 2. Register Tool

Add to `app/services/tools/registry.rb`:

```ruby
SYSTEM_TOOLS = {
  'my_tool' => Tools::System::MyTool,
  # ... other tools
}.freeze
```

### 3. Add to Orchestrator Toolset (if needed)

Add to `app/services/agents/orchestrator.rb` in appropriate toolset:

```ruby
TOOLSETS = {
  task_agent: %w[
    my_tool
    # ... other tools
  ]
}.freeze
```

Done! The tool will now:
- Appear in LLM context
- Execute when called
- Create a ThreadMessage with tool_activity metadata
- Render in iOS (if `is_user_facing: true`)

## Updating Tool ThreadMessages

Tools can update their own ThreadMessage during execution:

```ruby
def execute(title:)
  # Find this tool's message
  msg = ThreadMessage.find_by(tool_activity_id: @activity_id)

  # Update progress
  msg.update_tool_activity({ display_message: "Processing..." })

  # Do work
  result = process(title)

  # Update data
  msg.update_tool_activity_data({ result_id: result.id })

  success(result_id: result.id)
end
```

## Non-User-Facing Tools

Set `is_user_facing: false` for tools that don't need iOS cells:

```ruby
def self.metadata
  super.merge(
    name: 'internal_tool',
    description: 'Internal processing',
    is_user_facing: false  # No iOS cell
  )
end
```

These tools still create ThreadMessages but iOS won't render them as cells.
