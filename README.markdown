# MacLeod plugin for Movable Type #

This plugin facilitates the merging of two blogs in a "winner takes all" fashion in which a target blog literally absorbs content and author associations/permissions from another.  This renders the source blog a mostly empty, useless shell. (*"There can be only one"*).

The main reason for developing this tool was to handle blog consolidation and subsequent retiring of the absorbed blog as a separate entity.  For that reason, this tool was developed to change as little as possible in the underlying data, intelligently update the `blog_id`s of child classes instead of creating a new record via a clone.

## Features ##

* A command-line utility, `merge-blogs`, which facilitates the transfer of nearly all blog content and related metadata from one blog to another.

* A `dryrun` mode allowing you to run the process without actually modifying any data

* A set of detailed confirmation prompts that tell you exactly what will happen during execution and give you the ability to abort and a `force` mode to skip the interactive confirmations.

* The option (via the `perms` flag) to transfer user/group associations (i.e. permissions/roles) from the source blog to the target blog, creating in the target blog the logical union of both blog's users and assigned roles.

* The logging of all entry transfers with old and new permalink URLs which can be easily extracted for the purposes of setting up webserver redirects

* Designed to search for, discover and intelligently facilitate the transfer of data from arbitrary object types and classes (e.g. data from third-party plugins).

* Brief and lengthy documentation on the command line via the `help` and `man` flags


## Installation ##

To install this plugin follow the instructions found here:

http://tinyurl.com/easy-plugin-install

## Usage ##

There is no web interface for the plugin as everything is currently done entirely though its command-line utility at `plugins/MacLeod/tools/merge-blogs`.  Everything you need to know can be discovered in the utility's `man` page: 

    cd $MT_HOME
    ./plugins/MacLeod/tools/merge-blogs --man

## Pre-requisites ##

The following plugins/utilities are required for proper operation:

* Log4MT  - http://github.com/endevver/mt-plugin-log4mt
* CLITool - http://github.com/endevver/mt-util-clitool

## Limitations ##

The only blog-specific content not currently handled is:

* **Categories** - `MT::Category` and `MT::Placement` records.  This is currently pending functionality which will be added in the future
* **Templates** - `MT::Template` and `MT::TemplateMap` records. This was omitted because we questioned the need for it.  The new blog already has templates and we believe that most users would not want to move all of the templates *en masse* into the target blog.  We may develop a method to easily migrate selected templates upon users' requests.
* **Session, FileInfo and TheSchwartz records** - These are temporal and regenerated automatically as needed

## Help, Bugs and Feature Requests ##

If you are having problems installing or using the plugin, please check out our general knowledge base and help ticket system at [help.endevver.com](http://help.endevver.com).

## Copyright ##

Copyright 2010, Endevver, LLC. All rights reserved.

## License ##

This plugin is licensed under the GPL v2.

# About Endevver #

We design and develop web sites, products and services with a focus on 
simplicity, sound design, ease of use and community. We specialize in 
Movable Type and offer numerous services and packages to help customers 
make the most of this powerful publishing platform.

http://www.endevver.com/

