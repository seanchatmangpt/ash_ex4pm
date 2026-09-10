defmodule AshEx4pm.ObjectRelationship do
  @moduledoc """
  One `object_relationship` entity nested inside an `activity` entity --
  declares a real OCEL 2.0 O2O (object-to-object) fact: the acting
  resource's own record (the implicit "source" object -- this notifier
  emits exactly one primary object per notification, see
  `AshEx4pm.Notifier`'s moduledoc) is related to a target object reached
  via a real Ash relationship on the resource, with a named `qualifier`.

  `relationship` must name a real relationship declared on the owning
  resource (`Ash.Resource.Info.relationship/2`) -- validated by
  `AshEx4pm.Verifiers.Verify` at compile time, not just at emit time.
  """
  @enforce_keys [:relationship, :qualifier]
  defstruct [:relationship, :qualifier, :__identifier__, :__spark_metadata__]

  @type t :: %__MODULE__{
          relationship: atom(),
          qualifier: String.t()
        }
end

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

  `object_relationships` holds zero or more real
  `AshEx4pm.ObjectRelationship` entities declared inside this activity's
  own `do ... end` block -- see `AshEx4pm.ObjectRelationship`'s moduledoc
  and `AshEx4pm.Notifier.build_envelope/2`, which resolves each one's
  real target id from the notification's loaded relationship data.
  """
  @enforce_keys [:name, :on]
  defstruct [
    :name,
    :on,
    :resource,
    :object_type,
    attributes: [],
    qualifier: "primary",
    track_attribute_changes?: false,
    object_relationships: [],
    __identifier__: nil,
    __spark_metadata__: nil
  ]

  @type attribute_type :: :string | :integer | :float | :boolean | :atom | :date | :datetime
  @type t :: %__MODULE__{
          name: atom(),
          on: atom(),
          resource: module() | nil,
          object_type: atom() | nil,
          attributes: [{atom(), attribute_type()}],
          qualifier: String.t() | atom(),
          track_attribute_changes?: boolean(),
          object_relationships: [AshEx4pm.ObjectRelationship.t()]
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
  declaration is ash_ex4pm's own contract. `AshEx4pm.Transformers.Persist`
  checks each declared attribute's *type* is one of the allowed OCEL
  object-attribute types at compile time (an unsupported type, e.g. a
  typo'd `:strnig`, is refused at build time, not silently accepted) --
  it does NOT cross-check declared attribute names/types against the
  resource's own real Ash attributes (a declared object-type attribute
  with no matching Ash attribute on the resource still compiles; at emit
  time `AshEx4pm.Notifier.declared_attributes/2` does an uncoerced,
  untyped `Map.fetch` pass-through and simply omits whatever isn't
  present). Not re-validated downstream by ex4pm either way.
  """
  @enforce_keys [:name, :attributes]
  defstruct [:name, :attributes, :__identifier__, :__spark_metadata__]

  @type t :: %__MODULE__{
          name: atom(),
          attributes: keyword(atom())
        }
end

defmodule AshEx4pm.Dsl.ObjectRelationshipEntity do
  @moduledoc """
  Holds the real `object_relationship` `Spark.Dsl.Entity` definition behind
  a `__entity__/0` function -- the same indirection `ash`'s own nested-entity
  DSL modules use (e.g. `Ash.Reactor.Dsl.Actor.__entity__/0`,
  `~/ex4pm/deps/ash/lib/ash/reactor/dsl/create.ex:88`) for an entity that is
  itself nested inside another entity's own `do ... end` block, rather than
  a bare module-attribute reference (which is the correct pattern only for
  entities declared directly on a `Spark.Dsl.Section`).
  """
  def __entity__ do
    %Spark.Dsl.Entity{
      name: :object_relationship,
      describe:
        "Declares a real OCEL 2.0 O2O (object-to-object) fact for this activity: the " <>
          "acting resource's own record is related to the object reached via `relationship` " <>
          "with the given `qualifier`.",
      args: [:relationship, :qualifier],
      target: AshEx4pm.ObjectRelationship,
      identifier: {:auto, :unique_integer},
      schema: [
        relationship: [
          type: :atom,
          required: true,
          doc:
            "The name of a real Ash relationship declared on the owning resource " <>
              "(Ash.Resource.Info.relationship/2) whose loaded target record supplies " <>
              "the O2O fact's target object id and type."
        ],
        qualifier: [
          type: :string,
          required: true,
          doc: "The OCEL 2.0 qualifier for this relationship, e.g. \"placed_by\"."
        ]
      ]
    }
  end
end

defmodule AshEx4pm.Dsl do
  @moduledoc "Real `Spark.Dsl.Entity`/`Spark.Dsl.Section` definitions for `ex4pm do ... end`."

  @activity %Spark.Dsl.Entity{
    name: :activity,
    describe: "Declares a single OCEL activity emitted for one Ash action.",
    args: [:name, {:optional, :on}],
    target: AshEx4pm.Activity,
    identifier: :name,
    entities: [object_relationships: [AshEx4pm.Dsl.ObjectRelationshipEntity.__entity__()]],
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
      ],
      attributes: [
        type: :keyword_list,
        required: false,
        default: [],
        doc:
          "OCEL 2.0 event-type attribute schema for this activity, e.g. " <>
            "`attributes: [carrier: :string, weight: :integer]` -- a keyword " <>
            "list of `{name :: atom, type :: :string | :integer | :float | " <>
            ":boolean | :atom | :date | :datetime}` pairs. Distinct from " <>
            "`object_type`'s own `attributes:` (declared OBJECT attributes): this " <>
            "declares what an *event* of this activity always carries. " <>
            "AshEx4pm.Transformers.Persist validates every declared type against " <>
            "this allowed set at compile time; AshEx4pm.Notifier.build_envelope/2 " <>
            "reads these keys off the notification's data to populate the " <>
            "emitted event's real \"attributes\" map, rather than emitting " <>
            "whatever happens to be left over in the raw map."
      ],
      qualifier: [
        type: {:or, [:string, :atom]},
        required: false,
        default: "primary",
        doc:
          "The OCEL 2.0 relationship qualifier attached to this activity's single " <>
            "event-to-object relationship (AshEx4pm.Notifier.build_envelope/2's " <>
            "\"relationships\" => [%{\"qualifier\" => ...}] entry). Defaults to " <>
            "\"primary\" for backward compatibility with existing declarations. Set " <>
            "it to a semantically meaningful role (e.g. :orderer, :payer, \"shipped_to\") " <>
            "when the downstream ex4pm engine's e2o/o2o query predicates " <>
            "(Ex4pm.Cognition.Ocpq) need to distinguish this relationship from other " <>
            "activities' relationships on the same object type. Still scoped to " <>
            "one qualifier per activity -- see this notifier's own moduledoc " <>
            "\"Scope: single-object events only\" section for the multi-relationship " <>
            "escape hatch."
      ],
      track_attribute_changes?: [
        type: :boolean,
        required: false,
        default: false,
        doc:
          "Opt-in, composed on top of `attributes:` (never a replacement for it): " <>
            "when true and this activity's `on:` action is `:update`, " <>
            "AshEx4pm.Notifier.build_envelope/2 additionally captures every raw, " <>
            "PUBLIC (Ash.Resource.Info.public_attributes/1) attribute change present " <>
            "on the notification's changeset that this activity's own `attributes:` " <>
            "schema did NOT already declare, string-keyed, into the same emitted " <>
            "event \"attributes\" map. Declared/typed attributes always win on key " <>
            "collision. No effect on `:create` actions (no prior value exists to " <>
            "diff against) or when false (the default -- zero behavior change for " <>
            "existing activities)."
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
