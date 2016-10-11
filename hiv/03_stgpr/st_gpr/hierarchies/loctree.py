import sqlalchemy
import tree
import pandas as pd

def construct(location_set_version_id, location_set_id=None):
    """ Constructs and returns a tree representation of the location
    hierarchy specified by location_set_version_id """
    mysql_server  = 'mysql+pymysql://strConnection
    e = sqlalchemy.create_engine(mysql_server)
    c = e.connect()

    if location_set_id is not None:
        query = """
            SELECT  location_id,
                    parent_id,
                    is_estimate,
                    location_name,
                    location_name_short,
                    map_id,
                    location_type
            FROM shared.location_hierarchy
            JOIN shared.location USING(location_id)
            JOIN shared.location_type
                ON location.location_type_id = location_type.location_type_id
            WHERE location_set_id=%s """ % (location_set_id)
    else:
        query = """
        SELECT location_id, parent_id, is_estimate,
            location_hierarchy_history.location_name,
            location_hierarchy_history.location_name_short,
            location_hierarchy_history.map_id,
            location_hierarchy_history.location_type
        FROM shared.location_hierarchy_history
        JOIN shared.location USING(location_id)
        LEFT JOIN shared.location_type
            ON location_hierarchy_history.location_type_id = location_type.location_type_id
        WHERE location_set_version_id=%s """ % (location_set_version_id)

    locsflat = pd.read_sql(query, c.connection)
    root = locsflat[locsflat.location_id==locsflat.parent_id]
    root_node = tree.Node(root.location_id, root.to_dict('records')[0], None)

    # Construct all nodes
    nodes = {root_node.id: root_node}
    for i, row in locsflat[locsflat.location_id!=root_node.id].iterrows():
        node = tree.Node(row.location_id, row.to_dict(), None)
        nodes[node.id] = node

    # Assign parents
    for node_id, node in nodes.iteritems():
        if node_id!=node.info['parent_id']:
            node.parent = nodes[node.info['parent_id']]
            node.parent.add_child(node)

    loctree = tree.Tree(root_node)

    for node in loctree.nodes:
        if node.info['location_type'] in ['global','superregion','region']:
            name = node.info['location_name']
            name = name.replace(" ","_")
            name = name.replace(",","")
            name = name.replace("-","_")
            name = name.lower()
        elif node.id==8:
            node.info['map_id'] = "TWN"
            name = node.info['map_id']
        elif node.info['map_id'] is None:
            name = str(node.info['location_id'])
            if node.info['location_name']=='Sudan':
                node.info['map_id'] = 'SDN'
            elif node.info['location_name'] == 'South Sudan':
                node.info['map_id'] = 'SSD'
            else:
                try:
                    node.info['map_id'] = node.parent.info['map_id'] + '_' + str(node.info['location_id'])
                except:
                    if node.parent is not None:
                        if node.parent.id==4749:
                            node.info['map_id'] = "GBR_%s" % node.id
                            name = node.info['map_id']
                        else:
                            node.info['map_id'] = str(node.parent.info['location_id']) + '_' + str(node.info['location_id'])
                    else:
                        node.info['map_id'] = None
                name = node.info['map_id']
        else:
            name = node.info['map_id'].lower()
        node.info['dismod_name'] = name

    # Assign dismod levels
    for node in loctree.level_n_descendants(0):
        node.info['dismod_level'] = 'world'
    for node in loctree.level_n_descendants(1):
        node.info['dismod_level'] = 'super'
    for node in loctree.level_n_descendants(2):
        node.info['dismod_level'] = 'region'
    for node in loctree.level_n_descendants(3):
        node.info['dismod_level'] = 'subreg'
    for lvl in range(4,8):
        for node in loctree.level_n_descendants(lvl):
            node.info['dismod_level'] = 'atom'

    return loctree

if __name__ == "__main__":

    """ SAMPLE USAGE """
    loctree = construct(2)

    # Do potentially useful things...
    print '\nNode info:'
    print loctree.get_node_by_id(6).info

    print '\nNode ancestors:'
    print [x.info['location_name'] for x in loctree.get_node_by_id(6).ancestors()]
    print [x.info['location_type'] for x in loctree.get_node_by_id(6).ancestors()]

    print '\nNode children:'
    print [x.info['location_name'] for x in loctree.get_node_by_id(6).children]

    print '\nLowest level descendants (i.e. leaves):'
    print [x.info['location_name'] for x in loctree.get_node_by_id(6).leaves()]
