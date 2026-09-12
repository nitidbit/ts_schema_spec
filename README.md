# ts_schema_spec

Assert that a Rails payload matches the TypeScript type the React side
actually consumes.

TypeScript checks your own call sites. It cannot check props crossing
`react_component()` or a `render json:` boundary — those are `any` at runtime.
So a mismatch is silent: a missing key renders blank, a wrong type
mis-renders, and nothing fails.

This derives the JSON Schema from the `.tsx` the component already imports,
so there is no third artifact to keep in sync.

## Install

```ruby
# Gemfile
gem "ts_schema_spec", github: "nitidbit/ts_schema_spec", tag: "v0.1.0", group: :test
```

Pin the tag. Without one, Bundler follows the default branch, and
`bundle update` will pull an API change mid-port — `Skill.check!` compares the
installed skill against `TsSchemaSpec::VERSION`, which does not move as `main`
moves, so unpinned drift passes a check that ought to fail.

The generator parses your app's TypeScript, so it resolves from your
`node_modules` rather than being vendored:

```
npm install --save-dev ts-json-schema-generator
```

```ruby
# spec/rails_helper.rb
require "ts_schema_spec/rspec"
require "ts_schema_spec/react_component_props"

RSpec.configure do |config|
  config.include TsSchemaSpec::ReactComponentProps
end
```

### The agent skill

The gem ships the skill that teaches an agent when one of these specs is owed
and how to write it. Claude Code reads skills from the working tree, so it has
to be copied in and committed:

```
RAILS_ENV=test bundle exec rake ts_schema_spec:install_skill
```

`RAILS_ENV=test` is required when the gem is in `group: :test`, as above —
rake tasks come from the railtie, which only loads in an environment that
loads the gem, so the task simply does not exist in development. Add the gem
to `group :development, :test` if you would rather type less.

It lands in `.claude/skills/react-prop-type-spec/SKILL.md`, stamped with the
gem version. Guard it against drift — a stale skill teaches an API the gem no
longer has, which looks like it is working:

```ruby
# spec/ts_schema_spec_skill_spec.rb
it "has the skill matching the installed gem" do
  expect { TsSchemaSpec::Skill.check!(Rails.root) }.to_not raise_error
end
```

## Use

### A JSON endpoint

```ruby
ACCOUNT_TS = "app/javascript/types/account.ts"

it "matches AccountPayload" do
  get :index, format: :json

  expect(response).to be_successful
  expect(response.parsed_body["accounts"]).to match_schema(ACCOUNT_TS, "AccountPayload")
end
```

### Props from an HTML mount

`react_component_props` parses the rendered `data-react-props` attributes and
returns **an array** — one entry per mount of that component on the page. It
needs `render_views`.

```ruby
describe "the props handed to RoleMatrix" do
  render_views

  role_matrix = "app/javascript/components/roles/RoleMatrix.tsx"

  it "matches RoleMatrixProps" do
    create(:account, :with_roles)
    create(:account, :unassigned)

    get :show, params: { id: account.id }

    expect(response).to be_successful
    props = react_component_props("RoleMatrix")
    expect(props).to match_schema(role_matrix, "RoleMatrixProps")
  end
end
```

Pass the whole array. `match_schema` validates every item and fails on an
empty collection, so a page that stopped rendering the component fails rather
than passing vacuously — don't reach for `all`, which iterates zero times and
asserts nothing. Build two or three records with different traits so optional
fields, enum values and nil associations actually get exercised — one response
only covers the branches that response took.

## API

| Call                                    | Returns                                                |
| --------------------------------------- | ------------------------------------------------------ |
| `TsSchemaSpec.schema_for(path, type)`   | a `JSONSchemer` schema scoped to that exported type     |
| `match_schema(path, type)`              | matcher; validates an object, or every item of a collection |
| `react_component_props(name[, html])`   | array of props hashes, one per mount                    |
| `TsSchemaSpec::Skill.check!(root)`      | raises if the installed skill is stale or missing       |
| `TsSchemaSpec.clear_cache!`             | drops the per-file schema cache                         |

`path` is relative to Rails root, and goes at the assertion rather than in a
`let` — a schema bound once at the top of a describe block is how you end up
asserting one component's type against another's action. When several examples
read the same source, bind the path itself to a constant.

`schema_for` stays public for use outside RSpec; the matcher calls it for you,
and generation is cached per file, so naming the same source in twenty
examples costs one `npx` run.

## What a failure looks like

```
expected the payload to match the schema, but:
 - /id: value at `/id` is not a number
 - /created_at: object property at `/created_at` is a disallowed additional property
 - (root): object at root is missing required properties: shortcode

Payload was:
{
  "id": "1",
  "name": "Nurse",
  "created_at": "2026-09-11"
}
```

## Two things that will surprise you

**Undeclared keys fail.** `ts-json-schema-generator` emits
`additionalProperties: false`, so a payload carrying a key the TypeScript does
not declare is an error, not a warning. That is deliberate — it catches Rails
sending something nobody typed — but expect it when an `as_json` emits
timestamps the React side ignores. Fix by declaring the field or narrowing the
`only:`.

**An all-optional type asserts almost nothing.** A schema is only as strong as
the type it comes from; `shortcode?: string` passes whether the key is there
or not. If the server always sends a field, make it required, and use
`string | null` rather than `?` for a field that can be null. Tightening a
props type is an application change — give it its own commit.

## Cost

One `npx ts-json-schema-generator` invocation per **file** per suite run,
cached by path — reading three types out of one `.ts` costs one parse, not
three. The cache is per process, so parallel workers each pay it once.

## Troubleshooting

| Symptom                                              | Cause                                                        |
| ---------------------------------------------------- | ------------------------------------------------------------ |
| `GenerationError: ... Is it exported?`               | the type has no `export`, or the name is misspelled           |
| `GenerationError` listing a rerunnable command       | run it — the generator's own stderr is in the message         |
| passes against an obviously wrong payload            | the type is all-optional, or you scoped to the wrong type     |
| `disallowed additional property`                     | see above — the payload sends what TypeScript does not declare |

## What this can't catch

Worth knowing before you rely on it.

**Coverage is discipline-dependent.** This protects the actions somebody wrote
a spec for; an uncovered endpoint is exactly as exposed as before. That is what
the skill is for, and it is convention rather than enforcement.

**It only checks what TypeScript declares.** If Rails *intends* to send a field
nobody typed — say `as_json(only:)` carrying a misspelled attribute, which
Rails drops silently — no generated schema requires it, so nothing fails. A
structured serializer catches that class of mistake; this does not.

**One payload shape per example.** A single response only exercises the
branches it took. Nullable fields, empty collections and conditional
associations need records built to hit them.

## Why not generate the TypeScript instead?

If you can, do. [Typelizer](https://typelizer.dev/) and
[types_from_serializers](https://github.com/ElMassimo/types_from_serializers)
make Ruby canonical and generate the types, so drift becomes structurally
impossible rather than something you test for. That beats this.

They need serialization to exist somewhere nameable — they introspect Alba,
AMS, Oj, Panko or oj_serializers. An app that is plain `as_json` and
`render json:`, deciding payload shapes inline at each call site, has no
artifact for a generator to read. This gem is for that case: if a shape only
exists at its call site, the only way to learn it is to run the action and
look.

The other camp — [json_matchers](https://github.com/thoughtbot/json_matchers),
committee, rswag — validates against a hand-maintained JSON Schema file. That
is a third artifact to keep in sync with both sides, which is the same drift
problem relocated.

Even with generated types, `react_component` props stay uncovered: Typelizer
types serializer output and knows nothing about the outer props object
assembled in a view. That part is this gem's permanently.
