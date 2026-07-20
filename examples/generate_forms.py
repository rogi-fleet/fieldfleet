import re
import os

EXAMPLES_DIR = os.path.dirname(os.path.abspath(__file__))

with open(os.path.join(EXAMPLES_DIR, 'example_of_forms.html'), 'r') as f:
    lines = f.readlines()

header = "".join(lines[:586])
page_header_tmpl = "".join(lines[587:598])
footer = "".join(lines[5253:])

# Extract formTitles
form_titles_match = re.search(r'const formTitles = (\{.*?\});', footer, re.DOTALL)
if form_titles_match:
    form_titles_str = form_titles_match.group(1)
    # Basic parsing since it's almost JSON but not quite (single quotes, etc)
    # We'll just regex the keys and values
    titles = {}
    for match in re.finditer(r"form(\d+):\s*\[\s*'(.*?)',\s*'(.*?)'", form_titles_str):
        fid = f"form{match.group(1)}"
        titles[fid] = [match.group(2), match.group(3)]
else:
    print("Could not find formTitles")
    exit(1)

# Find all form panels
form_panels = []
current_form = None
current_content = []

for i, line in enumerate(lines):
    if '<div class="form-panel' in line:
        if current_form:
            form_panels.append((current_form, "".join(current_content)))
        
        # Extract ID
        id_match = re.search(r'id="(form\d+)"', line)
        current_form = id_match.group(1) if id_match else None
        current_content = [line]
    elif current_form:
        if i >= 5253: # End of main
            form_panels.append((current_form, "".join(current_content)))
            current_form = None
        elif '<div class="form-panel' in line: # Start of next (should have been caught above)
            pass
        else:
            # Check if this line is the start of the NEXT form panel
            # Actually our previous grep gave us the line numbers
            current_content.append(line)

# Wait, the above logic is a bit flawed because form panels are nested.
# Let's use the line numbers from grep.
form_starts = {
    "form1": 1356, "form2": 1808, "form3": 1978, "form4": 2225, "form5": 2505,
    "form6": 2724, "form7": 3148, "form8": 3457, "form9": 3720, "form10": 3881,
    "form11": 4013, "form12": 4113, "form13": 4226, "form14": 4324, "form15": 4436,
    "form16": 4540, "form17": 4647, "form18": 4743, "form19": 4850, "form20": 4950,
    "form21": 5047, "form22": 5144
}
sorted_ids = sorted(form_starts.keys(), key=lambda x: int(x[4:]))

for i, fid in enumerate(sorted_ids):
    start = form_starts[fid] - 1
    if i < len(sorted_ids) - 1:
        next_fid = sorted_ids[i+1]
        end = form_starts[next_fid] - 1
    else:
        end = 5254 - 1
    
    content = "".join(lines[start:end])
    # Clean up content (remove active class from others, add to this one)
    content = re.sub(r'class="form-panel active"', 'class="form-panel"', content)
    content = re.sub(r'id="{}"'.format(fid), 'id="{}" class="form-panel active"'.format(fid), content)
    
    title = titles[fid][0]
    subtitle = titles[fid][1]
    
    # Create file name
    slug = re.sub(r'[^a-z0-9]', '_', title.lower())
    slug = re.sub(r'_+', '_', slug).strip('_')
    filename = f"{fid}_{slug}.html"
    
    # Modify header for this file
    this_header = header
    # Update sidebar: set current to active, update all to links
    for other_fid in sorted_ids:
        other_title = titles[other_fid][0]
        other_slug = re.sub(r'[^a-z0-9]', '_', other_title.lower())
        other_slug = re.sub(r'_+', '_', other_slug).strip('_')
        other_filename = f"{other_fid}_{other_slug}.html"
        
        # Replace the button with a link if it's not already
        # Using regex to find the button for this fid
        pattern = r'<button class="form-nav-btn(.*?)" onclick="showForm\(\'{}\', this\)">'.format(other_fid)
        replacement = r'<a href="{}" class="form-nav-btn\1"'.format(other_filename)
        if other_fid == fid:
            replacement = r'<a href="{}" class="form-nav-btn active\1"'.format(other_filename)
        else:
            # Remove active class from others
            replacement = r'<a href="{}" class="form-nav-btn\1"'.format(other_filename)
            this_header = re.sub(r'<button class="form-nav-btn active" onclick="showForm\(\'{}\', this\)">'.format(other_fid), 
                                 '<button class="form-nav-btn" onclick="showForm(\'{}\', this\)">'.format(other_fid), this_header)

        this_header = re.sub(pattern, replacement, this_header)
    
    # Close the <a> tags
    this_header = this_header.replace('</button>', '</a>')
    
    # Set static page title and subtitle
    this_page_header = page_header_tmpl
    this_page_header = re.sub(r'id="pageTitle">.*?</div>', f'id="pageTitle">{title}</div>', this_page_header)
    this_page_header = re.sub(r'id="pageSubtitle">.*?</div>', f'id="pageSubtitle">{subtitle}</div>', this_page_header)

    full_html = this_header + this_page_header + content + footer
    
    with open(os.path.join(EXAMPLES_DIR, 'individual_forms', filename), 'w') as f_out:
        f_out.write(full_html)
