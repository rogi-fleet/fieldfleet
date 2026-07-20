-- Pin search_path on the three custom-field functions added in the previous
-- two migrations. Mitigates the advisor warning
-- "function_search_path_mutable" — without this, a malicious caller could
-- set their session search_path to a schema they control and shadow
-- helper objects.
ALTER FUNCTION public.enforce_custom_field_definitions_cap()
  SET search_path = public;

ALTER FUNCTION public.validate_project_custom_fields()
  SET search_path = public;

ALTER FUNCTION public.sync_project_custom_field_values()
  SET search_path = public;
