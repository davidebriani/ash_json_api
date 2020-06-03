defmodule AshJsonApi.JsonSchema do
  def generate(api) do
    resources =
      api
      |> Ash.resources()
      |> Enum.filter(&(AshJsonApi.JsonApiResource in &1.extensions()))

    route_schemas =
      Enum.flat_map(resources, fn resource ->
        resource
        |> AshJsonApi.routes()
        |> Enum.map(&route_schema(&1, api, resource))
      end)

    schema_id = "autogenerated_ash_json_api_schema"

    routes =
      if AshJsonApi.serve_schema(api) do
        [schema_schema(api, schema_id) | route_schemas]
      end

    definitions =
      Enum.reduce(resources, base_definitions(), fn resource, acc ->
        Map.put(acc, Ash.type(resource), resource_object_schema(resource))
      end)

    %{
      "$schema" => "http://json-schema.org/draft-06/schema#",
      "$id" => schema_id,
      "definitions" => definitions,
      "links" => routes
    }
  end

  def route_schema(%{method: method} = route, api, resource) when method in [:delete, :get] do
    {href, properties} = route_href(route, api)

    {href_schema, query_param_string} = href_schema(route, api, resource, properties)

    %{
      "href" => href <> query_param_string,
      "hrefSchema" => href_schema,
      "description" => "pending",
      "method" => route.method |> to_string() |> String.upcase(),
      "rel" => to_string(route.type),
      "targetSchema" => target_schema(route, api, resource),
      "headerSchema" => header_schema()
    }
  end

  def route_schema(route, api, resource) do
    {href, properties} = route_href(route, api)

    unless properties == [] or properties == ["id"] do
      raise "Haven't figured out more complex route parameters yet."
    end

    {href_schema, query_param_string} = href_schema(route, api, resource, properties)

    %{
      "href" => href <> query_param_string,
      "hrefSchema" => href_schema,
      "description" => "pending",
      "method" => route.method |> to_string() |> String.upcase(),
      "rel" => to_string(route.type),
      "schema" => route_in_schema(route, api, resource),
      "targetSchema" => target_schema(route, api, resource),
      "headerSchema" => header_schema()
    }
  end

  defp header_schema do
    # TODO: Figure this one out.

    # TODO: Raise different errors (415 vs 406) for incorrect content headers vs accept headers

    # For the content type header - I think we need a regex such as /^(application/vnd.api\+json;?)( profile=[^=]*";)?$/
    # This will ensure that it starts with "application/vnd.api+json" and only includes a profile param
    # I'm sure there will be a ton of edge cases so we may need to make a utility function for this and add unit tests

    # Here are some scenarios we should test:

    # application/vnd.api+json
    # application/vnd.api+json;
    # application/vnd.api+json; charset=\"utf-8\"
    # application/vnd.api+json; profile=\"utf-8\"
    # application/vnd.api+json; profile=\"utf-8\"; charset=\"utf-8\"
    # application/vnd.api+json; profile="foo"; charset=\"utf-8\"
    # application/vnd.api+json; profile="foo"
    # application/vnd.api+json; profile="foo8"
    # application/vnd.api+json; profile="foo";
    # application/vnd.api+json; profile="foo"; charset="bar"
    # application/vnd.api+json; profile="foo;";
    # application/vnd.api+json; profile="foo

    %{
      "type" => "object",
      "properties" => %{
        "content-type" => %{
          "type" => "array",
          "items" => %{
            "const" => "application/vnd.api+json"
          }
        },
        "accept" => %{
          "type" => "array",
          "items" => %{
            "type" => "string"
          }
        }
      },
      "additionalProperties" => true
    }
  end

  # This is for our representation of a resource *in the response*
  def resource_object_schema(resource) do
    %{
      "description" => "A \"Resource object\" representing a #{Ash.type(resource)}",
      "type" => "object",
      "required" => ["type", "id"],
      "properties" => %{
        "type" => %{
          "additionalProperties" => false
        },
        "id" => %{
          "type" => "string"
        },
        "attributes" => attributes(resource),
        "relationships" => relationships(resource)
        # "meta" => %{
        #   "$ref" => "#/definitions/meta"
        # }
      },
      "additionalProperties" => false
    }
  end

  defp schema_schema(api, schema_id) do
    href = Path.join(AshJsonApi.prefix(api) || "", "/schema")

    %{
      "href" => href,
      "method" => "GET",
      "rel" => "self",
      "targetSchema" => %{
        "$ref" => schema_id
      }
    }
  end

  defp base_definitions do
    %{
      "links" => %{
        "type" => "object",
        "additionalProperties" => %{
          "$ref" => "#/definitions/link"
        }
      },
      "link" => %{
        "description" =>
          "A link **MUST** be represented as either: a string containing the link's URL or a link object.",
        "type" => "string"
      },
      "errors" => %{
        "type" => "array",
        "items" => %{
          "$ref" => "#/definitions/error"
        },
        "uniqueItems" => true
      },
      "error" => %{
        "type" => "object",
        "properties" => %{
          "id" => %{
            "description" => "A unique identifier for this particular occurrence of the problem.",
            "type" => "string"
          },
          "links" => %{
            "$ref" => "#/definitions/links"
          },
          "status" => %{
            "description" =>
              "The HTTP status code applicable to this problem, expressed as a string value.",
            "type" => "string"
          },
          "code" => %{
            "description" => "An application-specific error code, expressed as a string value.",
            "type" => "string"
          },
          "title" => %{
            "description" =>
              "A short, human-readable summary of the problem. It **SHOULD NOT** change from occurrence to occurrence of the problem, except for purposes of localization.",
            "type" => "string"
          },
          "detail" => %{
            "description" =>
              "A human-readable explanation specific to this occurrence of the problem.",
            "type" => "string"
          },
          "source" => %{
            "type" => "object",
            "properties" => %{
              "pointer" => %{
                "description" =>
                  "A JSON Pointer [RFC6901] to the associated entity in the request document [e.g. \"/data\" for a primary data object, or \"/data/attributes/title\" for a specific attribute].",
                "type" => "string"
              },
              "parameter" => %{
                "description" => "A string indicating which query parameter caused the error.",
                "type" => "string"
              }
            }
          },
          "meta" => %{
            "$ref" => "#/definitions/meta"
          }
        },
        "additionalProperties" => false
      }
    }
  end

  defp attributes(resource) do
    %{
      "description" => "An attributes object for a #{Ash.type(resource)}",
      "type" => "object",
      "required" => required_attributes(resource),
      "properties" => resource_attributes(resource),
      "additionalProperties" => false
    }
  end

  defp required_attributes(resource) do
    resource
    |> AshJsonApi.fields()
    |> Enum.map(&Ash.attribute(resource, &1))
    |> Enum.reject(& &1.allow_nil?)
    |> Enum.map(&to_string(&1.name))
  end

  defp resource_attributes(resource) do
    resource
    |> AshJsonApi.fields()
    |> Enum.reduce(%{}, fn field, acc ->
      attr = Ash.attribute(resource, field)

      if attr do
        Map.put(acc, to_string(field), resource_field_type(resource, attr))
      else
        acc
      end
    end)
  end

  defp relationships(resource) do
    %{
      "description" => "A relationships object for a #{Ash.type(resource)}",
      "type" => "object",
      "properties" => resource_relationships(resource),
      "additionalProperties" => false
    }
  end

  defp resource_relationships(resource) do
    resource
    |> AshJsonApi.fields()
    |> Enum.reduce(%{}, fn field, acc ->
      rel = Ash.relationship(resource, field)

      if rel do
        data = resource_relationship_field_data(resource, rel)
        links = resource_relationship_link_data(resource, rel)

        object =
          if links do
            %{"data" => data, "links" => links}
          else
            %{"data" => data}
          end

        Map.put(
          acc,
          to_string(field),
          object
        )
      else
        acc
      end
    end)
  end

  defp resource_relationship_link_data(_resource, _rel) do
    # TODO: link to relationships when those routes are available
    nil
  end

  # TODO: When links are set up again, add those
  defp resource_relationship_field_data(_resource, %{
         cardinality: :one,
         destination: destination
       }) do
    %{
      "description" => "References to the related #{Ash.type(destination)}",
      anyOf: [
        %{
          "type" => "null"
        },
        %{
          "description" => "Resource identifiers of the related #{Ash.type(destination)}",
          "type" => "object",
          "required" => ["type", "id"],
          "additionalProperties" => false,
          "properties" => %{
            "type" => %{"const" => Ash.type(destination)},
            "id" => %{"type" => "string"}
            # TODO: support meta here.
          }
        }
      ]
    }
  end

  defp resource_relationship_field_data(_resource, %{
         cardinality: :many,
         destination: destination
       }) do
    %{
      "description" => "An array of references to the related #{Ash.type(destination)}",
      "type" => "array",
      "items" => %{
        "description" => "Resource identifiers of the related #{Ash.type(destination)}",
        "type" => "object",
        "required" => ["type", "id"],
        "properties" => %{
          "type" => %{"const" => Ash.type(destination)},
          "id" => %{"type" => "string"}
          # TODO: support meta here.
        }
      },
      "uniqueItems" => true
    }
  end

  defp resource_field_type(_resource, %{type: :string}) do
    %{
      "type" => "string"
    }
  end

  defp resource_field_type(_resource, %{type: :boolean}) do
    %{
      "type" => "boolean"
    }
  end

  defp resource_field_type(_resource, %{type: :integer}) do
    %{
      "type" => "integer"
    }
  end

  defp resource_field_type(_resource, %{type: :utc_datetime}) do
    %{
      "type" => "string",
      "format" => "date-time"
    }
  end

  defp resource_field_type(_resource, %{type: :uuid}) do
    %{
      "type" => "string",
      "format" => "uuid"
    }
  end

  defp resource_field_type(_, %{type: type}) do
    raise "unimplemented type #{type}"
  end

  defp href_schema(route, api, resource, properties) do
    base_properties =
      Enum.into(properties, %{}, fn prop ->
        {prop, %{"type" => "string"}}
      end)

    {query_param_properties, query_param_string} = query_param_properties(route, api, resource)

    {%{
       "required" => properties,
       "properties" => Map.merge(query_param_properties, base_properties)
     }, query_param_string}
  end

  defp query_param_properties(%{type: :index}, api, resource) do
    props = %{
      "filter" => %{
        "type" => "object",
        "properties" => filter_props(resource)
      },
      "sort" => %{
        "type" => "string",
        "format" => sort_format(resource)
      },
      "page" => %{
        "type" => "object",
        "properties" => page_props(api, resource)
      },
      "include" => %{
        "type" => "string",
        "format" => include_format(resource)
      }
    }

    {props, "{?filter,sort,page,include}"}
  end

  defp query_param_properties(_route, _api, resource) do
    props = %{
      "include" => %{
        "type" => "string",
        "format" => include_format(resource)
      }
    }

    {props, "{?include}"}
  end

  defp sort_format(resource) do
    sorts =
      resource
      |> AshJsonApi.fields()
      |> Enum.flat_map(fn field ->
        case Ash.attribute(resource, field) do
          nil ->
            []

          _attr ->
            [field, "-#{field}"]
        end
      end)

    "(#{Enum.join(sorts, "|")}),*"
  end

  defp page_props(_api, _resource) do
    %{
      "limit" => %{
        "type" => "string",
        "pattern" => "^[1-9][0-9]*$"
      },
      "offset" => %{
        "type" => "string",
        "pattern" => "^[1-9][0-9]*$"
      }
    }
  end

  defp include_format(_resource) do
    # TODO: include format
    "pending"
  end

  defp filter_props(resource) do
    resource
    |> AshJsonApi.fields()
    |> Enum.reduce(%{}, fn field, acc ->
      cond do
        attr = Ash.attribute(resource, field) ->
          Map.put(acc, to_string(field), attribute_filter_schema(attr))

        rel = Ash.relationship(resource, field) ->
          Map.put(acc, to_string(field), relationship_filter_schema(rel))

        true ->
          raise "Invalid field"
      end
    end)
  end

  defp attribute_filter_schema(attr) do
    # TODO make this better/incorporate validation!
    # Ideally, delegate this to some kind of `Ash.Type`
    case attr.type do
      :string ->
        %{
          "type" => "string"
        }

      :boolean ->
        %{
          "type" => "boolean"
        }

      :integer ->
        %{
          "type" => "integer"
        }

      :utc_datetime ->
        %{
          "type" => "string",
          "format" => "date-time"
        }
    end
  end

  defp relationship_filter_schema(_rel) do
    # TODO: For `to_many` relationships we should support passing a list of ids
    # or a comma separated list of ids
    # TODO: figure out the whole "id" type thing

    %{
      "type" => "string"
    }
  end

  defp route_in_schema(%{type: type}, _api, _resource) when type in [:index, :get, :delete] do
    %{}
  end

  defp route_in_schema(%{type: type}, _api, resource) when type in [:post] do
    %{
      "type" => "object",
      "required" => ["data"],
      "additionalProperties" => false,
      "properties" => %{
        "data" => %{
          "type" => "object",
          "additionalProperties" => false,
          "properties" => %{
            "type" => %{
              "const" => Ash.type(resource)
            },
            "attributes" => %{
              "type" => "object",
              "additionalProperties" => false,
              "required" => required_write_attributes(resource),
              "properties" => write_attributes(resource)
            },
            "relationships" => %{
              "type" => "object",
              "additionalProperties" => false,
              "properties" => write_relationships(resource)
            }
          }
        }
      }
    }
  end

  defp route_in_schema(%{type: type}, _api, resource) when type in [:patch] do
    %{
      "type" => "object",
      "required" => ["data"],
      "additionalProperties" => false,
      "properties" => %{
        "data" => %{
          "type" => "object",
          "additionalProperties" => false,
          "properties" => %{
            # TODO: We should use the primary key here, not rely on it being called id!
            "id" => resource_field_type(resource, Ash.attribute(resource, :id)),
            "type" => %{
              "const" => Ash.type(resource)
            },
            "attributes" => %{
              "type" => "object",
              "additionalProperties" => false,
              "properties" => write_attributes(resource)
            },
            "relationships" => %{
              "type" => "object",
              "additionalProperties" => false,
              "properties" => write_relationships(resource)
            }
          }
        }
      }
    }
  end

  defp route_in_schema(%{type: type}, _api, resource)
       when type in [:post_to_relationship, :patch_relationship, :delete_from_relationship] do
    %{
      "type" => "object",
      "required" => ["data"],
      "additionalProperties" => false,
      "properties" => %{
        "data" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["id", "type"],
            "properties" => %{
              # TODO: We should use the primary key here, not rely on it being called id!
              "id" => resource_field_type(resource, Ash.attribute(resource, :id)),
              "type" => %{
                "const" => Ash.type(resource)
              },
              "additionalProperties" => false
            }
          }
        }
      }
    }
  end

  defp required_write_attributes(resource) do
    resource
    |> AshJsonApi.fields()
    |> Enum.map(&Ash.attribute(resource, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(& &1.writable?)
    |> Enum.reject(& &1.allow_nil?)
    |> Enum.reject(& &1.default)
    |> Enum.reject(& &1.generated?)
    |> Enum.map(&to_string(&1.name))
  end

  defp write_attributes(resource) do
    resource
    |> AshJsonApi.fields()
    |> Enum.map(&Ash.attribute(resource, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(& &1.writable?)
    |> Enum.reduce(%{}, fn attribute, acc ->
      Map.put(acc, to_string(attribute.name), resource_field_type(resource, attribute))
    end)
  end

  defp write_relationships(resource) do
    resource
    |> AshJsonApi.fields()
    |> Enum.reduce(%{}, fn field, acc ->
      rel = Ash.relationship(resource, field)

      if rel do
        data = resource_relationship_field_data(resource, rel)
        links = resource_relationship_link_data(resource, rel)

        object =
          if links do
            %{"data" => data, "links" => links}
          else
            %{"data" => data}
          end

        Map.put(
          acc,
          to_string(field),
          object
        )
      else
        acc
      end
    end)
  end

  defp target_schema(route, _api, resource) do
    case route.type do
      :index ->
        %{
          "oneOf" => [
            %{
              "data" => %{
                "description" =>
                  "An array of resource objects representing a #{Ash.type(resource)}",
                "type" => "array",
                "items" => %{
                  "$ref" => "#/definitions/#{Ash.type(resource)}"
                },
                "uniqueItems" => true
              }
            },
            %{
              "$ref" => "#/definitions/errors"
            }
          ]
        }

      _ ->
        %{
          "oneOf" => [
            %{
              "data" => %{
                "$ref" => "#/definitions/#{Ash.type(resource)}"
              }
            },
            %{
              "$ref" => "#/definitions/errors"
            }
          ]
        }
    end
  end

  defp route_href(route, api) do
    {path, path_params} =
      api
      |> AshJsonApi.prefix()
      |> Kernel.||("")
      |> Path.join(route.route)
      |> Path.split()
      |> Enum.reduce({[], []}, fn part, {path, path_params} ->
        case part do
          ":" <> name -> {["{#{name}}" | path], [name | path_params]}
          part -> {[part | path], path_params}
        end
      end)

    {path |> Enum.reverse() |> Path.join(), path_params}
  end
end
