import pandas as pd


class Tree:
    """ A basic tree class """

    def __init__(self, root):
        """ Initiates the class with a root node """
        self.root = root
        self.nodes = [root]
        self.nodes.extend(Node.all_descendants(self.root))
        self.node_ids = [ n.id for n in self.nodes ]

    def all_descendants(self):
        return self.root.all_descendants()

    def level_n_descendants(self, n):
        return self.root.level_n_descendants(n)

    def leaves(self):
        return self.root.leaves()

    def max_depth(self):
        """Returns the maximum level of depth in the tree (where the root
        is at depth=0"""
        lvl = 1
        has_lvl_desc = True
        while has_lvl_desc:
            num_children = len(self.level_n_descendants(lvl))
            if num_children==0:
                has_lvl_desc = False
            else:
                lvl+=1
        return lvl-1

    def get_node_by_id(self, id):
        """Returns the node in the tree specified by id if it exists,
        otherwise returns None."""
        for n in self.nodes:
            if n.id==id:
                return n
        return None

    def get_nodelvl_by_id(self, id):
        """Returns the level of the node specified by id,
        otherwise returns None."""
        node = self.get_node_by_id(id)
        if node is not None:
            return len(node.ancestors())
        else:
            return None

    def add_node(self, id, info, parent_id):
        """Creates a single node and adds it to the tree as a child of
        the parent_id node"""
        assert id not in self.node_ids, "Node id already exists in tree"

        parent_node = self.get_node_by_id(parent_id)
        assert parent_id in self.node_ids, "Parent does not exist in tree"

        new_node = Node(id, info, parent_node)
        self.node_ids.append(id)
        self.nodes.append(new_node)

    def prune(self, id):
        """Removes a node and all of it's descendants from the tree"""
        assert id in self.node_ids, "Node id does not exist in tree"
        assert id!=self.root.id, "Cannot prune at root node"

        # Remove child from parent node
        self.get_node_by_id(id).parent.remove_child(id)

        # Remove child and all its descendants from node list
        self.remove_child_nodes(id)

    def remove_child_nodes(self, id):
        """Removes all child nodes of the specified node"""
        children = self.get_node_by_id(id).children
        self.nodes = [ n for n in self.nodes if n.id!=id ]
        if len(children)>0:
            for c in children:
                self.remove_child_nodes(c.id)

    def to_dict(self):
        """Converts the tree to a nested dictionary"""
        def node_to_dict(node):
            if len(node.children)==0:
                return node.info
            else:
                info_dict = node.info.copy()
                info_dict['children'] = []
                for c in node.children:
                    info_dict['children'].append(node_to_dict(c))
                return info_dict
        d = node_to_dict(self.root)
        return d

    def flatten(self):
        """Converts tree to a 'de-normalized' form, i.e. a table"""
        df = pd.DataFrame([{'level_0': self.root.id}])
        for lvl in range(1, self.max_depth()+1):
            loc_pairs = [(l.parent.id, l.id) for l in self.level_n_descendants(lvl)]
            loc_pairs = pd.DataFrame(loc_pairs)
            loc_pairs.rename(columns={
                0: 'level_'+str(lvl-1),
                1: 'level_'+str(lvl)}, inplace=True)
            df = df.merge(loc_pairs, on='level_'+str(lvl-1), how='left')
        df['leaf_node'] = df.apply(lambda x:
            next(l for l in reversed(x) if pd.notnull(l)), axis=1)

        for c in df.columns:
            try:
                df[c] = df[c].astype('int')
            except:
                pass

        return df

    def db_format(self):
        """Converts tree to the parent-child format used in the
        GBD hierarchy databases"""
        def gen_p2p_str(node):
            anc_ids = [a.id for a in node.ancestors()]
            anc_ids.reverse()
            anc_ids = anc_ids+[node.id]
            return ','.join([str(aid) for aid in anc_ids])

        db_dict = { 'location_id': [self.root.id],
                'parent_id': [self.root.id],
                'path_to_top_parent': [gen_p2p_str(self.root)],
                'level': [0] }

        for lvl in range(1,self.max_depth()+1):
            nodes = self.level_n_descendants(lvl)
            for n in nodes:
                db_dict['location_id'].append(n.id)
                db_dict['parent_id'].append(n.parent.id)
                db_dict['path_to_top_parent'].append(gen_p2p_str(n))
                db_dict['level'].append(lvl)

        db_df = pd.DataFrame(db_dict)
        leaf_ids = [l.id for l in self.leaves()]
        db_df['most_detailed'] = 0
        db_df.ix[db_df.location_id.isin(leaf_ids), 'most_detailed'] = 1
        return db_df


class Node:
    """
    A basic node class, with navigation to parent and child nodes

    Attributes:
        id: An int (or castable to int) that uniquely identifies the
        node
        info: Any structure containing the node's contents
        parent: The node that is parent to this node. Assumes that
        each node has at most one parent node. Can be set to None.
    """

    def __init__(self, id, info, parent):
        """ Initilizes the node """
        self.id = int(id)
        self.info = info
        self.parent = parent
        self.children = []
        if parent is not None:
            self.parent.add_child(self)

    def all_descendants(self):
        """ Returns all the node's descendants """
        return Node.s_all_descendants(self)

    def level_n_descendants(self, n):
        """ Returns all the node's nth level descendants, with the
        node's level itself being 0 """
        return Node.s_level_n_descendants(self, n)

    def leaves(self):
        """ Returns the node's terminal desceandants (i.e. leaves) """
        return Node.s_leaves(self)

    def add_child(self, child):
        """ Adds a child to the node's list of children """
        self.children.append(child)

    def remove_child(self, child_id):
        """ Removes a child node """
        self.children = [ c for c in self.children if c.id!= child_id ]

    def get_children(self):
        """ Returns the node's immediate children (equivalent to the
        1st level children) """
        return self.children

    def ancestors(self):
        """ Returns the node's ancestors, in order of proximity """
        return Node.s_ancestors(self)

    @staticmethod
    def s_level_n_descendants(node, n):
        """ Finds and returns the node's nth level descendants """
        if n==0:
            return [node]
        else:
            children = []
            for child in node.children:
                children.extend(Node.s_level_n_descendants(child, n-1))
            return children

    @staticmethod
    def s_all_descendants(node):
        """ Finds and returns all the node's descendants """
        if len(node.children)==0:
            return []
        else:
            children = node.children[:]
            for child in node.children:
                children.extend(Node.s_all_descendants(child))
            return children

    @staticmethod
    def s_leaves(node):
        """ Finds and returns all the node's terminal descendants
        (i.e. leaves) """
        if len(node.children)==0:
            return [node]
        else:
            desc_leaves = []
            for child in node.children:
                desc_leaves.extend(Node.s_leaves(child))
            return desc_leaves

    @staticmethod
    def s_ancestors(node):
        """ Finds and returns (in order of proximity) all the node's
        ancestors """
        if node.parent==None:
            return []
        else:
            anc = [node.parent]
            anc.extend(Node.s_ancestors(node.parent))
            return anc

    def __repr__(self):
        return str(self.id)

    def __str__(self):
        return str(self.id)


def unflatten_to_tree(df, label_map=None, label_col='label', id_col='id'):
    """ Converts a 'flat' tree representation (i.e. a table of the form
    produced by Tree's 'flatten' method, into Tree instance """

    tf_df = df.filter(like='level')
    n_lvls = len(tf_df.columns)
    lvl_list = range(n_lvls)

    # Construct all nodes
    uniq_ids = pd.Series(pd.unique(tf_df.values.ravel()))
    uniq_ids = uniq_ids.dropna()

    if label_map is not None:
        assert len(set(uniq_ids)-set(label_map[label_col].unique()))==0, '''
                If a label_map is specified, all labels in df must
                be present in the map '''
        rdict = { r[label_col]: r[id_col] for i, r in label_map.iterrows() }
        tf_df = tf_df.replace(rdict)
        uniq_ids = pd.Series(pd.unique(tf_df.values.ravel()))
        uniq_ids = uniq_ids.dropna()
    uniq_ids = uniq_ids.astype('int')

    assert len(tf_df['level_0'].unique())==1, '''there can only be
            one level_0 id'''
    root_id = tf_df['level_0'].unique()[0]

    nodes = {}
    for nid in uniq_ids:
        nodes[nid] = Node(nid, {}, None)

    # Make relationships
    for i in lvl_list:
        lvl_col = 'level_%s' % i
        nxtlvl_col = 'level_%s' % (i+1)
        assert ~tf_df[lvl_col].isin(tf_df.drop(lvl_col, axis=1)).any(), '''
            ids cannot span multiple levels'''

        if i<lvl_list[-1]:
            for pnid in tf_df[lvl_col].unique():
                child_locs = pd.Series(tf_df.ix[tf_df[lvl_col]==pnid,
                        nxtlvl_col].unique()).dropna()
                for cnid in child_locs:
                    nodes[cnid].parent = nodes[pnid]
                    nodes[pnid].add_child(nodes[cnid])

    t = Tree(nodes[root_id])
    return t


def parent_child_to_tree(df, parent_col, child_col):

    assert len(df[df[child_col]==df[parent_col]])==1, '''There must be
        one and only one root node, specified where
        child_col==parent_col'''
    root_id = df.ix[df[child_col]==df[parent_col], parent_col].values[0]
    root_node = Node(root_id, {}, None)
    nodes = {root_id: root_node}

    non_roots = df[df[child_col]!=df[parent_col]]
    for nid in non_roots[child_col].unique():
        nodes[nid] = Node(nid, {}, None)

    for i, row in non_roots.iterrows():
        cnid = row[child_col]
        pnid = row[parent_col]
        nodes[cnid].parent = nodes[pnid]
        nodes[pnid].add_child(nodes[cnid])

    t = Tree(nodes[root_id])
    return t


if __name__=="__main__":
    n1 = Node(1,1,None)
    n2 = Node(2,1,n1)
    n3 = Node(3,1,n1)
    n4 = Node(4,1,n3)
    n5 = Node(5,1,n4)
    n6 = Node(6,1,n2)
    n7 = Node(7,1,n1)
    n8 = Node(8,1,n1)

    t1 = Tree(n1)
    t2 = Tree(n2)
    t3 = Tree(n3)

    flatdf = pd.read_csv("unflat_test2.csv")
    tfromflat = unflatten_to_tree(flatdf)

    flatdf2 = pd.read_csv("unflat_test3.csv")
    label_map = pd.read_csv("label_map.csv")

    dbtree = tfromflat.db_format()
