# Extracting and Reordering Sections

Select, replace, and move Markdown sections based on heading structure.

## Overview

Section APIs treat headings as section boundaries. A section begins at a heading and continues until the next heading at the same or higher level. This makes extraction and reordering preserve nested content under the selected heading.

Use section extraction when you need one part of a document by heading name or position. Use section reordering when you need to move a section among its sibling sections without flattening the document hierarchy.

## Important Behavior

Section movement is sibling-aware. Moving a section up, down, or to a specific sibling position does not arbitrarily move it across unrelated heading levels.
