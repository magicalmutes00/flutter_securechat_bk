/// True when [value] is a well-formed UUID string (any version).
///
/// Used to reject malformed identifiers in route paths before they reach a
/// parameterized SQL query.
final _uuidRegExp = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool isValidUuid(String value) => _uuidRegExp.hasMatch(value);
