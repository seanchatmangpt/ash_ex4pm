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
    :__identifier__,
    :__spark_metadata__,
    object_relationships: []
  ]

  @type t :: %__MODULE__{
          name: atom(),
          on: atom(),
          resource: module() | nil,
          object_relationships: [AshEx4pm.ObjectRelationship.t()]
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
      ]
    ]
  }

  @ex4pm %Spark.Dsl.Section{
    name: :ex4pm,
    describe: "Declares which Ash actions emit real OCEL 2.0 events via ex4pm.",
    entities: [@activity],
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
