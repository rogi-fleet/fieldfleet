import os
import re

dir_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'individual_forms')
for filename in os.listdir(dir_path):
    if filename.endswith('.html'):
        path = os.path.join(dir_path, filename)
        with open(path, 'r') as f:
            content = f.read()
        
        # Fix the duplicated class attribute
        content = re.sub(r'class="form-panel"\s+id="(form\d+)"\s+class="form-panel active"', r'class="form-panel active" id="\1"', content)
        
        with open(path, 'w') as f:
            f.write(content)
