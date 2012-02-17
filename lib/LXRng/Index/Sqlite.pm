# Copyright (C) 2012 Marcel Lauhoff <ml-lxr@irq0.0.org>
# Copyright (C) 2008 Arne Georg Gleditsch <lxr@linux.no>.
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# The full GNU General Public License is included in this distribution
# in the file called COPYING.

package LXRng::Index::Sqlite;

use strict;
use DBI;

use base qw(LXRng::Index::DBI);

sub dbh {
    my ($self) = @_;

    return $$self{'dbh'} if $$self{'dbh'};

    $$self{'dbh'} = DBI->connect('dbi:SQLite:dbname='.$$self{'db_file'},
				 "",
				 "",
				 {AutoCommit => 1,
				  RaiseError => 1})
	or die($DBI::errstr);
    $$self{'dbh_pid'} = $$;

    $$self{'dbh'}->do("PRAGMA recursive_triggers = ON");

    return $$self{'dbh'};
}

sub init_db {
    my ($self) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    $dbh->{AutoCommit} = 0;

    $dbh->do(qq{
	create table ${pre}charsets
	    (
	     id			integer primary key autoincrement,
	     name		varchar
	     )
	}) or die($dbh->errstr);

    $dbh->do(qq{insert into ${pre}charsets(name) values ('ascii')})
	or die($dbh->errstr);
    $dbh->do(qq{insert into ${pre}charsets(name) values ('utf-8')})
	or die($dbh->errstr);
    $dbh->do(qq{insert into ${pre}charsets(name) values ('iso-8859-1')})
	or die($dbh->errstr);

    $dbh->do(qq{
	create table ${pre}trees
	    (
	     id			integer primary key autoincrement,
	     name		varchar unique
	     )
	}) or die($dbh->errstr);

    $dbh->do(qq{
	create table ${pre}releases
	    (
	     id			integer primary key autoincrement,
	     id_tree		int references ${pre}trees(id),
	     release_tag	varchar,
	     is_indexed		bool default 'f'
	     )
	}) or die($dbh->errstr);

    $dbh->do(qq{
	create table ${pre}files
	    (
	     id			integer primary key autoincrement,
	     path		varchar unique
	     )
	}) or die($dbh->errstr);

    $dbh->do(qq{
	create table ${pre}revisions
	    (
	     id			integer primary key autoincrement,
	     id_file		integer references ${pre}files(id),
	     revision		varchar,
	     last_modified_gmt	timestamp without time zone, -- GMT
	     last_modified_tz	varchar(5), -- Optional TZ
	     body_charset	int references ${pre}charsets(id),
	     unique		(id_file, revision)
	     )
	}) or die($dbh->errstr);

    $dbh->do(qq{
	create table ${pre}filestatus
	    (
	     id_rfile		int references ${pre}revisions(id),
	     indexed		bool default 'f',
	     referenced		bool default 'f',
	     hashed		bool default 'f',
	     primary key	(id_rfile)
	     )
	}) or die($dbh->errstr);

    $dbh->do(qq{
	create table ${pre}hashed_documents
	    (
	     id_rfile		int references ${pre}revisions(id),
	     doc_id		int not null,
	     primary key	(id_rfile)
	     )
	}) or die($dbh->errstr);

    $dbh->do(qq{
	create table ${pre}filereleases
	    (
	     id_rfile		int,
	     id_release		int,
	     primary key	(id_rfile, id_release)
	     )
	}) or die($dbh->errstr);

    $dbh->do(qq{
	create table ${pre}includes
	    (
	     id_rfile		int references ${pre}revisions(id),
	     id_include_path	int references ${pre}files(id)
	     )
	}) or die($dbh->errstr);

    $dbh->do(qq{
	create table ${pre}symbols
	    (
	     id			integer primary key autoincrement,
	     name		varchar unique
	     )
	}) or die($dbh->errstr);

    $dbh->do(qq{
	create table ${pre}identifiers
	    (
	     id 		integer primary key autoincrement,
	     id_symbol		int references ${pre}symbols(id) deferrable,
	     id_rfile		int references ${pre}revisions(id) deferrable,
	     line		int,
	     type		char(1),
	     context		int references ${pre}identifiers(id) deferrable
	     )
	}) or die($dbh->errstr);

    $dbh->do(qq{
	create table ${pre}usage
	    (
	     id_rfile		int,
	     id_symbol		int,
	     lines		int[]
	     )
	}) or die($dbh->errstr);

    $dbh->do(qq{create index ${pre}symbol_idx1 on ${pre}symbols (name)})
	or die($dbh->errstr);
    $dbh->do(qq{create index ${pre}ident_idx1 on ${pre}identifiers (id_symbol)})
	or die($dbh->errstr);
    $dbh->do(qq{create index ${pre}ident_idx2 on ${pre}identifiers (id_rfile)})
	or die($dbh->errstr);
    $dbh->do(qq{create index ${pre}ident_idx3 on ${pre}identifiers (id_symbol, id_rfile)})
	or die($dbh->errstr);
    $dbh->do(qq{create index ${pre}usage_idx1 on ${pre}usage (id_symbol)})
	or die($dbh->errstr);
    $dbh->do(qq{create index ${pre}usage_idx2 on ${pre}usage (id_rfile)})
	or die($dbh->errstr);
    $dbh->do(qq{create index ${pre}include_idx1 on ${pre}includes (id_rfile)})
	or die($dbh->errstr);
    $dbh->do(qq{create index ${pre}file_idx1 on ${pre}files (path)})
	or die($dbh->errstr);
    $dbh->do(qq{create index ${pre}filerel_idx1 on ${pre}filereleases (id_release)})
	or die($dbh->errstr);

    $dbh->commit();
    $dbh->{AutoCommit} = 0;
}

sub drop_db {
    my ($self) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    local($dbh->{RaiseError}) = 0;

    $dbh->do(qq{drop index ${pre}symbol_idx1});
    $dbh->do(qq{drop index ${pre}ident_idx1});
    $dbh->do(qq{drop index ${pre}ident_idx2});
    $dbh->do(qq{drop index ${pre}usage_idx1});
    $dbh->do(qq{drop index ${pre}usage_idx2});
    $dbh->do(qq{drop index ${pre}include_idx1});
    $dbh->do(qq{drop index ${pre}file_idx1});
    $dbh->do(qq{drop index ${pre}filerel_idx1});

    $dbh->do(qq{drop table ${pre}usage});
    $dbh->do(qq{drop table ${pre}identifiers});
    $dbh->do(qq{drop table ${pre}symbols});
    $dbh->do(qq{drop table ${pre}includes});
    $dbh->do(qq{drop table ${pre}filereleases});
    $dbh->do(qq{drop table ${pre}hashed_documents});
    $dbh->do(qq{drop table ${pre}filestatus});
    $dbh->do(qq{drop table ${pre}revisions});
    $dbh->do(qq{drop table ${pre}files});
    $dbh->do(qq{drop table ${pre}releases});
    $dbh->do(qq{drop table ${pre}trees});
    $dbh->do(qq{drop table ${pre}charsets});

}

sub _add_tree {
    my ($self, $tree) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_add_tree_ins'} ||=
	$dbh->prepare(qq{insert or replace into ${pre}trees(name) values (?)});
    $sth->execute($tree);

    my ($id) = $dbh->last_insert_id("","","${pre}trees", "id");

    $sth->finish();

    return $id;
}

sub _add_release {
    my ($self, $tree_id, $release) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_add_relase_ins'} ||=
	$dbh->prepare(qq{insert into ${pre}releases(id_tree, release_tag)
			     values (?, ?)});
    $sth->execute($tree_id, $release);

    my ($id) = $dbh->last_insert_id("","","${pre}releases", "id");
    $sth->finish();
    return $id;
}

sub _add_file {
    my ($self, $path) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;

    my $sth = $$self{'sth'}{'_add_file_ins'} ||=
	$dbh->prepare(qq{insert or replace into ${pre}files(path) values (?)});



    $sth->execute($path);

    my ($id) = $dbh->last_insert_id("","","${pre}files", "id");

    $sth->finish();

    return $id;
}

sub _get_rfile {
    my ($self, $file_id, $revision) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_get_rfile'} ||=
	$dbh->prepare(qq{select id, strftime('%s', last_modified_gmt, 'UTC')
                         from ${pre}revisions where id_file = ? and revision = ?});

    my ($id, $gmt);
    if ($sth->execute($file_id, $revision)) {
	($id, $gmt) = $sth->fetchrow_array();
    }
    $sth->finish();

    return ($id, $gmt);
}

sub _add_rfile {
    my ($self, $file_id, $revision, $time) = @_;

    my ($epoch, $zone) = $time =~ /^(\d+)(?: ([-+]\d\d\d\d)|)$/;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_add_rfile_ins'} ||=
	$dbh->prepare(qq{
	    insert or replace into ${pre}revisions(id_file, revision,
					last_modified_gmt,
					last_modified_tz)
		values (?, ?,
			datetime(?, 'unixepoch'), ?)});

    $sth->execute($file_id, $revision, $epoch, $zone)
	or die($dbh->errstr);

    my ($id) = $sth->fetchrow_array();
    my ($id) = $dbh->last_insert_id("","","${pre}revisions","id");

    $sth->finish();

    return $id;
}

sub _update_rfile_timestamp {
    my ($self, $rfile_id, $time) = @_;

    my ($epoch, $zone) = $time =~ /^(\d+)(?: ([-+]\d\d\d\d)|)$/;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_update_rfile_timestamp'} ||=
	$dbh->prepare(qq{
	    update ${pre}revisions set
		last_modified_gmt = datetime(?, 'unixepoch'),
		last_modified_tz = ?
		where id = ?});

    $sth->execute($epoch, $zone, $rfile_id)
	or die($dbh->errstr);
    $sth->finish();
}

sub _add_filerelease {
    my ($self, $rfile_id, $rel_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_add_filerelease'} ||=
	$dbh->prepare(qq{insert into ${pre}filereleases(id_rfile, id_release)
			     select ?, ? where not exists
			     (select 1 from ${pre}filereleases
			      where id_rfile = ? and id_release = ?)});
    $sth->execute($rfile_id, $rel_id, $rfile_id, $rel_id);
}

sub _add_symbol {
    my ($self, $symbol) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_add_symbol_ins'} ||=
	$dbh->prepare(qq{insert into ${pre}symbols(name) values (?)});
    $sth->execute($symbol);

    my ($id) = $dbh->last_insert_id("","","${pre}symbols", "id");

    $sth->finish();

    return $id;
}

sub _add_ident {
    my ($self, $rfile_id, $line, $sym_id, $type, $ctx_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_add_ident_ins'} ||=
	$dbh->prepare(qq{insert into ${pre}identifiers
			     (id_rfile, line, id_symbol, type, context)
			     values (?, ?, ?, ?, ?)});
    $sth->execute($rfile_id, $line, $sym_id, $type, $ctx_id);

    my ($id) = $dbh->last_insert_id("","","${pre}identifiers", "id");

    $sth->finish();

    return $id;
}

sub _add_usage {
    my ($self, $file_id, $symbol_id, $lines) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_add_usage'} ||=
	$dbh->prepare(qq{insert into ${pre}usage(id_rfile, id_symbol, lines)
			     values (?, ?, ?)});
    $sth->execute($file_id, $symbol_id, '{'.join(',', @$lines).'}');

    return 1;
}

sub _identifiers_by_name {
    my ($self, $rel_id, $symbol) = @_;

    my $sym_id = $self->_get_symbol($symbol);
    my $dbh = $self->dbh;
    my $pre = $self->prefix;

    my $sth = $$self{'sth'}{'_identifiers_by_name'} ||=
      $dbh->prepare(qq{
	     select i.id, i.type, f.path, i.line, i.id_rfile
		from ${pre}identifiers i, ${pre}files f,
			 ${pre}filereleases r, ${pre}revisions v
		where i.id_rfile = v.id and v.id = r.id_rfile
		and r.id_release = ? and v.id_file = f.id
		and i.type != 'm' and i.type != 'l'
		and i.id_symbol = ?
	    union
	     select i.id, i.type, f.path, i.line, i.id_rfile
		from ${pre}identifiers i, ${pre}files f,
			 ${pre}filereleases r, ${pre}revisions v
		where i.id_rfile = v.id and v.id = r.id_rfile
		and r.id_release = ? and v.id_file = f.id
		and (i.type = 'm' or i.type = 'l')
		and i.id_symbol = ? limit 250});

    $sth->execute($rel_id, $sym_id, $rel_id, $sym_id);
    my $res = $sth->fetchall_arrayref();

    return $res;
}

sub get_rfile_timestamp {
    my ($self, $rfile_id) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;

    my $sth = $$self{'sth'}{'get_rfile_timestamp'} ||=
      $dbh->prepare(qq{
	    select strftime('%s', last_modified_gmt),
                   last_modified_tz
		from ${pre}revisions where id = ?});

    unless ($sth->execute($rfile_id) == 1) {
	return undef;
    }

    my ($epoch, $tz) = $sth->fetchrow_array();
    $sth->finish();

    return ($epoch, $tz);
}



sub DESTROY {
    my ($self) = @_;

    if ($$self{'dbh'}) {
	if ($$self{'dbh_pid'} != $$) {
	    $$self{'dbh'}->{InactiveDestroy} = 1;
	    undef $$self{'dbh'};
	}
	else {
	    $$self{'dbh'}->rollback();
	    $$self{'dbh'}->disconnect();
	    delete($$self{'dbh'});
	}
    }
}

1;
