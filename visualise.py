import re
import graphviz
import os
from pathlib import Path
from collections import defaultdict

class VerilogParser:
    def __init__(self):
        self.modules = {}  # All modules found
        self.hierarchy = defaultdict(list)  # Module hierarchy
        self.connections = []  # Wire connections
        self.module_files = {}  # Which file contains which module
        
    def parse_directory(self, directory):
        """Parse all Verilog files in directory and build hierarchy"""
        verilog_files = list(Path(directory).glob('**/*.v'))
        print(f"Found {len(verilog_files)} Verilog files:")
        
        # First pass: collect all module definitions
        for file in verilog_files:
            print(f"Processing: {file}")
            self._parse_module_definitions(file)
            
        # Second pass: build hierarchy and connections
        for file in verilog_files:
            self._parse_module_hierarchy(file)
            
        # Build complete hierarchy tree
        self._build_hierarchy_tree()
        
    def _parse_module_definitions(self, filepath):
        """First pass: collect module definitions"""
        with open(filepath, 'r') as file:
            content = file.read()
        
        # Remove comments
        content = re.sub(r'//.*?\n', '\n', content)
        content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
        
        # Find all module definitions
        module_matches = re.finditer(r'module\s+(\w+)\s*\(([\s\S]*?)\);([\s\S]*?)endmodule', content)
        
        for match in module_matches:
            module_name = match.group(1)
            port_list = match.group(2)
            module_body = match.group(3)
            
            self.modules[module_name] = {
                'file': str(filepath),
                'ports': self._parse_ports(port_list),
                'wires': self._parse_wires(module_body),
                'instances': [],
                'connections': []
            }
            self.module_files[module_name] = filepath.stem
            
    def _parse_ports(self, port_list):
        """Parse module ports"""
        ports = {
            'input': [],
            'output': [],
            'inout': []
        }
        
        # Split port list and classify
        for port in port_list.split(','):
            port = port.strip()
            if port:
                # Check for input/output/inout keywords
                for port_type in ['input', 'output', 'inout']:
                    if port_type in port:
                        name = re.sub(r'.*' + port_type + r'\s*(?:\[[\w:-]+\])?\s*', '', port)
                        ports[port_type].append(name.strip())
                        break
        
        return ports
    
    def _parse_wires(self, module_body):
        """Parse wire declarations"""
        wires = []
        wire_matches = re.finditer(r'wire\s*(?:\[[\w:-]+\])?\s*([\w\s,]+);', module_body)
        for match in wire_matches:
            wire_list = match.group(1).replace(' ', '').split(',')
            wires.extend(wire_list)
        return wires
    
    def _parse_module_hierarchy(self, filepath):
        """Second pass: build hierarchy and connections"""
        with open(filepath, 'r') as file:
            content = file.read()
        
        # Remove comments
        content = re.sub(r'//.*?\n', '\n', content)
        content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
        
        # Find module instantiations
        for parent_match in re.finditer(r'module\s+(\w+)', content):
            parent_module = parent_match.group(1)
            
            # Find all instantiations in this module
            inst_matches = re.finditer(
                r'(\w+)\s+(\w+)\s*\(([\s\S]*?)\);',
                content[parent_match.end():]
            )
            
            for inst_match in inst_matches:
                module_type = inst_match.group(1)
                instance_name = inst_match.group(2)
                port_connections = inst_match.group(3)
                
                # Skip if not a known module type
                if module_type not in self.modules:
                    continue
                
                # Record instantiation
                self.modules[parent_module]['instances'].append({
                    'type': module_type,
                    'name': instance_name,
                    'connections': self._parse_connections(port_connections)
                })
                
                # Add to hierarchy
                self.hierarchy[parent_module].append(module_type)
                
    def _parse_connections(self, port_connections):
        """Parse port connections in module instantiation"""
        connections = []
        
        # Split by comma, handling nested parentheses
        ports = []
        current_port = ''
        paren_count = 0
        
        for char in port_connections:
            if char == '(':
                paren_count += 1
            elif char == ')':
                paren_count -= 1
            elif char == ',' and paren_count == 0:
                if current_port.strip():
                    ports.append(current_port.strip())
                current_port = ''
                continue
            current_port += char
            
        if current_port.strip():
            ports.append(current_port.strip())
        
        # Parse each port connection
        for port in ports:
            port = port.strip()
            if port:
                match = re.match(r'\.(\w+)\((.*?)\)', port)
                if match:
                    connections.append({
                        'port': match.group(1),
                        'wire': match.group(2).strip()
                    })
        
        return connections
    
    def _build_hierarchy_tree(self):
        """Build complete hierarchy tree from top modules down"""
        self.top_modules = set(self.modules.keys())
        
        # Remove modules that are instantiated by others
        for parent, children in self.hierarchy.items():
            for child in children:
                if child in self.top_modules:
                    self.top_modules.remove(child)
    
    def create_visualization(self):
        """Create hierarchical visualization"""
        dot = graphviz.Digraph(name='verilog_hierarchy')
        dot.attr(rankdir='TB')  # Top to bottom layout
        
        # Create clusters for files
        file_modules = defaultdict(list)
        for module_name, module_info in self.modules.items():
            file_modules[Path(module_info['file']).stem].append(module_name)
        
        # Create subgraphs for each file
        for file_name, modules_in_file in file_modules.items():
            with dot.subgraph(name=f'cluster_{file_name}') as c:
                c.attr(label=file_name, style='rounded', bgcolor='lightgrey')
                
                # Add modules in this file
                for module_name in modules_in_file:
                    module_info = self.modules[module_name]
                    
                    # Create module label with ports and wires
                    label = f'{module_name}\\n'
                    if module_info['ports']['input']:
                        label += '\\nInputs:\\n' + '\\n'.join(module_info['ports']['input'])
                    if module_info['ports']['output']:
                        label += '\\nOutputs:\\n' + '\\n'.join(module_info['ports']['output'])
                    if module_info['wires']:
                        label += '\\nWires:\\n' + '\\n'.join(module_info['wires'])
                    
                    # Add module node
                    node_color = 'lightblue' if module_name in self.top_modules else 'white'
                    c.node(module_name, label=label, shape='record', style='filled', fillcolor=node_color)
                    
                    # Add connections for instances
                    for instance in module_info['instances']:
                        # Create edge from parent to child module
                        edge_label = f'{instance["name"]}\\n'
                        edge_label += '\\n'.join(f"{conn['port']} → {conn['wire']}" 
                                               for conn in instance['connections'])
                        
                        dot.edge(module_name, instance['type'], 
                               label=edge_label, 
                               color='blue',
                               fontcolor='darkblue')
        
        return dot

def main():
    # Initialize parser
    parser = VerilogParser()
    
    # Get current directory
    directory = os.getcwd()
    print(f"Processing Verilog files in: {directory}")
    
    # Parse all files and build hierarchy
    parser.parse_directory(directory)
    
    # Create and save visualization
    print("\nCreating visualization...")
    diagram = parser.create_visualization()
    
    # Set reasonable size and DPI for large diagrams
    diagram.attr(size='50,50')
    
    print("Rendering diagram...")
    output_file = 'verilog_hierarchy'
    diagram.render(output_file, format='png', cleanup=True)
    print(f"\nVisualization saved as: {output_file}.png")
    
    # Print hierarchy information
    print("\nModule Hierarchy:")
    print("\nTop-level modules:")
    for top_module in parser.top_modules:
        print(f"- {top_module} (in {parser.module_files[top_module]})")
        
    print("\nModule dependencies:")
    for parent, children in parser.hierarchy.items():
        if children:
            print(f"\n{parent} (in {parser.module_files[parent]}) instantiates:")
            for child in children:
                print(f"  - {child} (in {parser.module_files[child]})")

if __name__ == '__main__':
    main()