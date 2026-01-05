defmodule MtgDeckBuilder.AI.ExpertTools do
  @moduledoc """
  Defines the tools available to the orchestrator for consulting specialist experts.

  Each tool represents a specialist that can be consulted for specific types of questions.
  The orchestrator decides which experts to consult based on the user's question.
  """

  @doc """
  Returns the tool definitions for Anthropic's tool use format.
  """
  @spec tool_definitions() :: [map()]
  def tool_definitions do
    [
      %{
        name: "consult_mana_expert",
        description: """
        Consult the mana base expert for questions about:
        - Land counts and ratios
        - Color source requirements
        - Mana curve alignment
        - Mana fixing (dual lands, fetches, etc.)
        - Color pip requirements analysis
        - Mulligan considerations related to mana
        """,
        input_schema: %{
          type: "object",
          properties: %{
            question: %{
              type: "string",
              description: "The specific mana-related question to ask the expert"
            },
            focus_areas: %{
              type: "array",
              items: %{type: "string"},
              description: "Specific aspects to focus on (e.g., 'color sources', 'curve', 'fixing')"
            }
          },
          required: ["question"]
        }
      },
      %{
        name: "consult_synergy_expert",
        description: """
        Consult the synergy and interactions expert for questions about:
        - Card combinations and synergies
        - Non-obvious interactions
        - Enablers and payoffs
        - "Secret tech" card suggestions
        - Cards that unlock other cards' potential
        - Package recommendations (groups of cards that work together)
        """,
        input_schema: %{
          type: "object",
          properties: %{
            question: %{
              type: "string",
              description: "The specific synergy-related question to ask the expert"
            },
            cards_to_analyze: %{
              type: "array",
              items: %{type: "string"},
              description: "Specific cards to analyze for synergies"
            }
          },
          required: ["question"]
        }
      },
      %{
        name: "consult_card_evaluator",
        description: """
        Consult the card evaluation expert for questions about:
        - Card role assessment (what does this card do for the deck?)
        - Upgrade suggestions (better versions of current cards)
        - Alternative card options
        - "X is better than Y" comparisons
        - Cut recommendations (what to remove)
        - Card quality in context of the deck's strategy
        """,
        input_schema: %{
          type: "object",
          properties: %{
            question: %{
              type: "string",
              description: "The specific card evaluation question to ask the expert"
            },
            cards_to_evaluate: %{
              type: "array",
              items: %{type: "string"},
              description: "Specific cards to evaluate"
            },
            evaluation_context: %{
              type: "string",
              description: "Context for evaluation (e.g., 'for aggressive matchups', 'budget alternatives')"
            }
          },
          required: ["question"]
        }
      },
      %{
        name: "consult_meta_expert",
        description: """
        Consult the metagame and matchups expert for questions about:
        - Current format metagame
        - Popular decks and their strategies
        - Hate cards and sideboard options
        - Matchup analysis
        - Sideboard priorities
        - Positioning the deck in the meta
        """,
        input_schema: %{
          type: "object",
          properties: %{
            question: %{
              type: "string",
              description: "The specific meta-related question to ask the expert"
            },
            matchups_of_interest: %{
              type: "array",
              items: %{type: "string"},
              description: "Specific matchups to analyze (e.g., 'vs Burn', 'vs Control')"
            }
          },
          required: ["question"]
        }
      },
      %{
        name: "consult_rules_expert",
        description: """
        Consult the rules expert for questions about:
        - Complex card interactions
        - Timing and priority questions
        - Stack interactions
        - State-based actions
        - Layer system questions
        - Tournament rules clarifications
        """,
        input_schema: %{
          type: "object",
          properties: %{
            question: %{
              type: "string",
              description: "The specific rules question to ask the expert"
            },
            cards_involved: %{
              type: "array",
              items: %{type: "string"},
              description: "Cards involved in the rules question"
            }
          },
          required: ["question"]
        }
      },
      %{
        name: "recommend_cards",
        description: """
        Add cards to the user's deck. Use this tool when recommending specific cards.

        IMPORTANT - Choose the right board:
        - "mainboard" - Use for complete deck builds (user asked for "a deck", "build me X")
        - "sideboard" - Use for sideboard recommendations
        - "staging" - Use for suggestions to consider, upgrades, or alternatives

        ALWAYS use this tool when making card recommendations so users can see them!
        """,
        input_schema: %{
          type: "object",
          properties: %{
            cards: %{
              type: "array",
              items: %{
                type: "object",
                properties: %{
                  name: %{type: "string", description: "Exact card name"},
                  quantity: %{type: "integer", description: "Number of copies (1-4 for most cards)"},
                  reason: %{type: "string", description: "Brief reason for recommendation"}
                },
                required: ["name", "quantity"]
              },
              description: "List of cards to recommend"
            },
            board: %{
              type: "string",
              enum: ["mainboard", "sideboard", "staging"],
              description: "Where to put the cards. Use 'mainboard' for deck builds, 'sideboard' for sideboard, 'staging' for suggestions to consider."
            }
          },
          required: ["cards", "board"]
        }
      },
      %{
        name: "set_brew_settings",
        description: """
        Set the deck's brew settings (archetype and/or colors).
        Use this when the user specifies what kind of deck they want to build.

        Examples:
        - User says "aggro deck" → set archetype to "aggro"
        - User says "orzhov aggro" → set archetype to "aggro", colors to ["W", "B"]
        - User says "blue control" → set archetype to "control", colors to ["U"]
        """,
        input_schema: %{
          type: "object",
          properties: %{
            archetype: %{
              type: "string",
              enum: ["aggro", "midrange", "control", "combo", "tempo", "ramp"],
              description: "The deck archetype"
            },
            colors: %{
              type: "array",
              items: %{type: "string", enum: ["W", "U", "B", "R", "G"]},
              description: "Deck colors (W=White, U=Blue, B=Black, R=Red, G=Green)"
            }
          }
        }
      }
    ]
  end

  @doc """
  Checks if a tool is an action tool (not an expert consultation).
  """
  @spec is_action_tool?(String.t()) :: boolean()
  def is_action_tool?("recommend_cards"), do: true
  def is_action_tool?("set_brew_settings"), do: true
  def is_action_tool?(_), do: false

  @doc """
  Returns the list of expert names for validation.
  """
  @spec expert_names() :: [String.t()]
  def expert_names do
    ["mana_expert", "synergy_expert", "card_evaluator", "meta_expert", "rules_expert"]
  end

  @doc """
  Maps a tool name to an agent_id for lookup.
  """
  @spec tool_to_agent_id(String.t()) :: String.t()
  def tool_to_agent_id("consult_mana_expert"), do: "mana_expert"
  def tool_to_agent_id("consult_synergy_expert"), do: "synergy_expert"
  def tool_to_agent_id("consult_card_evaluator"), do: "card_evaluator"
  def tool_to_agent_id("consult_meta_expert"), do: "meta_expert"
  def tool_to_agent_id("consult_rules_expert"), do: "rules_expert"
  def tool_to_agent_id(unknown), do: raise("Unknown tool: #{unknown}")
end
