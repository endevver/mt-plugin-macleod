# MacLeod plugin for Movable Type #

This plugin facilitates the process of blog consolidation in which one blog's content/associations are transferred entirely to another

merging of two blogs in a "winner takes all" fashion in which a target blog literally absorbs content and author associations/permissions from another.  This renders the source blog a mostly empty, useless shell.

The main reason for developing this tool was to handle blog consolidation and subsequent retiring of the absorbed blog as a separate entity.  For that reason, this tool was developed to change as little as possible in the underlying data, intelligently update the `blog_id`s of child classes instead of creating a new record via a clone.

Though it seems inconceivable that an explanation would be necessary, the name of the plugin is a [Highlander](http://en.wikipedia.org/wiki/Highlander_(film)) reference. *There can be only one!*

## Features ##

* A command-line utility, `merge-blogs`, which facilitates the transfer of nearly all blog content and related metadata from one blog to another.

* A `dryrun` mode allowing you to run the process without actually modifying any data

* A set of detailed confirmation prompts that tell you exactly what will happen during execution and give you the ability to abort and a `force` mode to skip the interactive confirmations.

* The option (via the `perms` flag) to transfer user/group associations (i.e. permissions/roles) from the source blog to the target blog, creating in the target blog the logical union of both blog's users and assigned roles.

* The logging of all entry transfers with old and new permalink URLs which can be easily extracted for the purposes of setting up webserver redirects

* Designed to search for, discover and intelligently facilitate the transfer of data from arbitrary object types and classes (e.g. data from third-party plugins).

* Supports merging of categories and their placement records as directed by a user-customized CSV file. This functionality requires the Text::CSV perl module and is executed under a different run mode as well as a third which does nothing but verify the CSV file. Unfortunately, the documentation here on GitHub is lacking as this was designed to the commissioning client's spec.  If you need guidance before I complete it, drop me a line.

* Brief and lengthy documentation of the [command line utility](http://github.com/endevver/mt-plugin-macleod/blob/master/plugins/MacLeod/tools/merge-blogs) via the `help` and `man` flags

## Installation ##

To install this plugin follow the instructions found here:

http://tinyurl.com/easy-plugin-install

## Usage ##

There is no web interface for the plugin as everything is currently done entirely though its command-line utility at `plugins/MacLeod/tools/merge-blogs`.  Everything you need to know can be discovered in the utility's `man` page: 

    cd $MT_HOME
    ./plugins/MacLeod/tools/merge-blogs --man

## Pre-requisites ##

The following plugins/utilities are required for proper operation:

* [Log4MT](http://github.com/endevver/mt-plugin-log4mt) - Used for general purpose logging and recording of entry permalink redirects
* [CLITool](http://github.com/endevver/mt-util-clitool) - Underlying framework for all of Endevver's command-line interface (CLI) tools

## Limitations ##

You can see a full list of the data types **not handled** by the system in the [config.yaml](http://github.com/endevver/mt-plugin-macleod/blob/master/plugins/MacLeod/config.yaml).  In general, the only blog-specific content not currently handled is:

* **Templates** - `MT::Template` and `MT::TemplateMap` records. This was omitted because we questioned the need for it.  The new blog already has templates and we believe that most users would not want to move all of the templates *en masse* into the target blog.  We may develop a method to easily migrate selected templates upon users' requests.
* **Session, FileInfo and TheSchwartz records** - These are temporal and regenerated automatically as needed

## Help, Bugs and Feature Requests ##

If you are having problems installing or using the plugin, please check out our general knowledge base and help ticket system at [help.endevver.com](http://help.endevver.com).

## Future Plans ##

This plugin was quickly put together to satisfy a single use case for a client.  In the future, it will certainly be expanded (and properly named) to facilitate mobility of individual pieces of content, all objects from individual object classes (e.g. templates, associations, etc) and metadata between blogs.

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

