defmodule AshEx4pm.Activity do
  @moduledoc """
  One `activity :name, on: :action` entity inside an `ex4pm do ... end`
  block. Mirrors the plain-struct DSL entity shape `ash_r2rml`'s
  `AshR2RML.Resource` uses for its own entities
  (`~/ash_r2rml/lib/ash_r2rml/resource.ex:68-102`) -- a real struct, not
  an anonymous map.

  `resource` is filled in automatically by `AshEx4pm.Transformers.Persist`
  when this entity is declared inside a resource's own `ex4pm do ... end`
  block (never set explicitly there); it must be supplied explicitly when
  the entity is declared at the domain level. This is the real
  `AshAi.Transformers.ResourceTools` context-normalization pattern
  (`~/xaas/deps/ash_ai/lib/ash_ai/transformers/resource_tools.ex:13-55,125-127`),
  reused here via `ash-extension-core-pack` v26.9.10's `aex:contextNormalize`
  vocabulary.

  `object_type` is optional: an atom naming a declared `object_type`
  entity in the same `ex4pm do ... end` block/section (see
  `AshEx4pm.ObjectType`). `AshEx4pm.Transformers.Persist` refuses to
  compile if it does not resolve. When unset, `AshEx4pm.Notifier`
  preserves its historical behavior of deriving an OCEL object type from
  the resource's own module name -- this is a real, disclosed
  back-compat fallback, not schema-checked, and stays the extension's
  single biggest OCEL 2.0 nonconformance for any resource that does not
  opt into `object_type:`.
  """
  @enforce_keys [:name, :on]
  defstruct [:name, :on, :resource, :object_type, :__identifier__, :__spark_metadata__]

  @type t :: %__MODULE__{
          name: atom(),
          on: atom(),
          resource: module() | nil,
          object_type: atom() | nil
        }
end

defmodule AshEx4pm.ObjectType do
  @moduledoc """
  One `object_type :name, attributes: [...]` entity inside an
  `ex4pm do ... end` block -- a real, declared OCEL 2.0 object-type
  schema entry (`ocel:objectTypes`), not the emergent-from-module-name
  behavior `AshEx4pm.Notifier.resource_type_name/1` falls back to when no
  `object_type` is declared for an activity.

  `attributes` is a keyword list of `attribute_name :: ocel_attribute_type`
  pairs, e.g. `[total_amount: :decimal, currency: :string]`. Types are
  plain atoms describing the OCEL attribute's declared value type
  (`:string`, `:integer`, `:float`, `:decimal`, `:boolean`, `:datetime`,
  `:date`) -- ex4pm's own `Ex4pm.OCEL.validate_envelope/1`
  (`~/ex4pm/lib/ex4pm/ocel.ex:366-417`) does not itself enforce an
  attribute-type schema on ingest (confirmed by reading it: an object's
  "attributes" map is opaque, passed through as-is), so this type
  declaration is ash_ex4pm's own contract, checked at compile time
  against a resource's own Ash attributes by
  `AshEx4pm.Transformers.Persist`, not re-validated downstream by ex4pm.
  """
  @enforce_keys [:name, :attributes]
  defstruct [:name, :attributes, :__identifier__, :__spark_metadata__]

  @type t :: %__MODULE__{
          name: atom(),
          attributes: keyword(atom())
        }
end

defmodule AshEx4pm.Dsl do
  @moduledoc "Real `Spark.Dsl.Entity`/`Spark.Dsl.Section` definitions for `ex4pm do ... end`."

  @activity %Spark.Dsl.Entity{
    name: :activity,
    describe: "Declares a single OCEL activity emitted for one Ash action.",
    args: [:name, {:optional, :on}],
    target: AshEx4pm.Activity,
    identifier: :name,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The OCEL activity name this Ash action emits, e.g. :order_created."
      ],
      on: [
        type: :atom,
        required: true,
        doc:
          "The Ash action name (e.g. :create) that triggers this activity. Always " <>
            "required -- there is no implicit per-action inference; see " <>
            "AshEx4pm.Activity's @enforce_keys, which mirrors this requirement."
      ],
      resource: [
        type: :atom,
        required: false,
        doc:
          "The Ash resource this activity applies to. Set automatically by " <>
            "AshEx4pm.Transformers.Persist for resource-level declarations; required " <>
            "explicitly for domain-level declarations. Setting it explicitly at the " <>
            "resource level is a compile error (see AshEx4pm.Transformers.Persist)."
      ],
      object_type: [
        type: :atom,
        required: false,
        doc:
          "The name of a declared `object_type` entity (see AshEx4pm.ObjectType) this " <>
            "activity's emitted object conforms to. Must resolve to a declared " <>
            "`object_type` in the same section -- AshEx4pm.Transformers.Persist refuses " <>
            "to compile otherwise. When unset, the OCEL object type is derived from the " <>
            "resource's own module name (AshEx4pm.Notifier.resource_type_name/1), a " <>
            "real, disclosed back-compat fallback with no declared attribute contract."
      ]
    ]
  }

  @object_type %Spark.Dsl.Entity{
    name: :object_type,
    describe:
      "Declares a real OCEL 2.0 object-type schema entry: a name plus a typed " <>
        "attribute list, machine-checkable against activities and, at emit time, " <>
        "against the acting resource's own Ash attributes.",
    args: [:name],
    target: AshEx4pm.ObjectType,
    identifier: :name,
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The declared OCEL object type name, e.g. :order."
      ],
      attributes: [
        type: :keyword_list,
        required: false,
        default: [],
        doc:
          "A keyword list of `attribute_name :: ocel_attribute_type` pairs declared for " <>
            "this object type, e.g. `[total_amount: :decimal, currency: :string]`. See " <>
            "AshEx4pm.ObjectType's moduledoc for the supported type atoms."
      ]
    ]
  }

  @ex4pm %Spark.Dsl.Section{
    name: :ex4pm,
    describe: "Declares which Ash actions emit real OCEL 2.0 events via ex4pm.",
    entities: [@activity, @object_type],
    schema: [
      provenance_source: [
        type: :atom,
        required: false,
        default: :ash_ex4pm,
        doc:
          "Tagged into every emitted event's metadata.source field " <>
            "(Ex4pm.Event.metadata), so events generated by this extension are " <>
            "distinguishable from hand-constructed or other-source events."
      ]
    ]
  }

  def section, do: @ex4pm
end
