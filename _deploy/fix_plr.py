path = "/home/biqu/printer_data/config/01__User_Custom__CFG/PLR_2xExtr_carto.cfg"
with open(path) as f:
    content = f.read()

old = '''[gcode_macro _save_z_resume]
gcode:
    {% set svv = printer.save_variables.variables %}
    {% set z_probe = printer["probe"].last_z_result %}
    {% set p_offset = printer.configfile.settings["probe"]["z_offset"]|float %} #current z_offset for the probe
    SAVE_VARIABLE VARIABLE=z_resume VALUE={( z_probe - p_offset )|round(3)} '''

new = '''[gcode_macro _save_z_resume]
gcode:
    {% set z_pos = printer.gcode_move.gcode_position.z %}
    SAVE_VARIABLE VARIABLE=z_resume VALUE={z_pos|round(3)}'''

if old in content:
    content = content.replace(old, new)
    with open(path, 'w') as f:
        f.write(content)
    print('Fixed _save_z_resume')
else:
    print('ERROR: Could not find exact text')
