# popm
Payo OpenPrograms Manager (a replacement for oppm)

so, features for popm (not sorted by priority) [not currently in oppm].

1. option to cache repo list
--1. would be an optional parameter. default is download repo list every time. 
2. option to cache pkg defintions
--1. a cached pkg definition would block updates, but speed up installs for new packages. also, i plan to leverage the pkg cache through pcp to remote update/remote/install pkgs.
3. store relative install path in installation database
--1. oppm lets you give a custom install path for pkgs. subsequent updates reuse that install path - the user doesn't have to specify it again. Right now, the oppm db only stores installed file paths. a pkg could move files to the point that upon an update, oppm would not know where to install the new files. currently oppm uses a path pattern regex to determine where the install path was. but if no files from the update match any installed files - it would be impossible to determine the right path. the db needs the relative path.
4. store file version (git checksum)
--1. oppm only stores installed file paths. no versions. thus updates are full downloads and replacements of all files.
5. create update tree
--1. oppm updates every installed package and all of its dependencies, with no redundancy checks.
6. store user-installed packages in a "world" file
--1. oppm does not distinguish user-installed versus dependency-installed packages. popm will be able to notify a user that a package is unreferenced (after an uninstall) - and give the user the option to remove it (the user may actually be using it - in which case the user should install it to add it to the world file
7. (addon to #6) add pkg to world file
--1. gentoo emerge has this to allow a user to add a pkg to the world - a way to keep a pkg referenced. for example, user may decide they like payo-lib and want it to remain referenced after uninstalling psh
8. option to pre-fetch (default), interlaced-fetch, post-fetch
--1. pre-fetch (default): download ALL files from ALL updates/installs first, then remove all files marked for removal/update, then install (move) all cached files. This is the safest method of the 3, but also the most space hungry option. The update/install will fail prematurely if the machine runs out of free space (in oc, hdd size is resource)
--2. interlaced-fetch: for each pkg: remove all files marked for deletion then for each file for update: remove existing file, download update in its place. this is a more interactive experience, visually. It is slightly unsafe, a package could remain in a broken state, but also does not require any extra space.
--3. post-fetch: remove all files marked for deletion or update, then download all updates to their destinations. The most unsafe - but included for completeness. Not sure why someone would prefer this over interlaced.
9. list files installed from a package
10. preview list of packages that would be updated
11. use local repos defintion as a auxiliary appendix to the official online repos file
--1. right now, oppm uses the online repos.cfg for the list of official repos ( https://raw.githubusercontent.com/OpenPrograms/openprograms.github.io/master/repos.cfg ) and a local oppm.cfg for users that want custom, non-public, packages (e.g. https://raw.githubusercontent.com/payonel/payonel-Programs-staging/master/oppm.cfg ). But the local oppm.cfg is a mix of the repos.cfg and programs.cfg, which is not conducive to a staging environment. I want a local repos.cfg that acts as an extension of the online repos.cfg (SAME FORMAT). I could append to the repos list, or even replace entries by using the same keys (to point to a staging github, for example). With popm, oppm.cfg would be ignored. If it detects one, it'd warn the user to get with the program.
12. option to exclusively use local repos.cfg and not read from the official repos.cfg
13. provide all of these features as an api exposed as a lua library (like argutil is)
14. allow custom install path to be a remote host (over psh and pcp)
