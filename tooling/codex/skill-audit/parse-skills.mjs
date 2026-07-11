function parseSection(text, start, endMarkers) {
  const startIndex = text.indexOf(start);
  if (startIndex === -1) return "";

  const sectionStart = startIndex + start.length;
  const markers = Array.isArray(endMarkers) ? endMarkers : [endMarkers];
  const endIndexes = markers
    .map((marker) => text.indexOf(marker, sectionStart))
    .filter((index) => index >= 0);
  const sectionEnd = endIndexes.length ? Math.min(...endIndexes) : undefined;
  return text.slice(sectionStart, sectionEnd);
}

export function parseRoots(text) {
  const section = parseSection(text, "### Skill roots", "### Available skills");
  const roots = {};
  for (const line of section.split("\n")) {
    const match = line.match(/^- `(r\d+)` = `(.+)`$/);
    if (match) roots[match[1]] = match[2];
  }
  return roots;
}

export function parseAvailableSkills(text) {
  const section = parseSection(text, "### Available skills", [
    "### How to use skills",
    "</skills_instructions>",
  ]);
  const skills = [];

  for (const line of section.split("\n")) {
    if (!line.startsWith("- ") || !line.endsWith(")")) continue;

    const fileMarker = "(file: ";
    const fileMarkerIndex = line.lastIndexOf(fileMarker);
    if (fileMarkerIndex === -1) continue;

    const labelAndDescription = line.slice(2, fileMarkerIndex).trimEnd();
    const nameEnd = labelAndDescription.indexOf(": ");
    if (nameEnd === -1) continue;

    skills.push({
      name: labelAndDescription.slice(0, nameEnd),
      fileRef: line.slice(fileMarkerIndex + fileMarker.length, -1),
    });
  }

  return skills;
}
