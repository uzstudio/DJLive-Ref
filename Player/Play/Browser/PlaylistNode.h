/*
 *  $Id$
 *
 *  Copyright (C) 2006 - 2007 Stephen F. Booth <me@sbooth.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#import <Cocoa/Cocoa.h>
#import "AudioStreamCollectionNode.h"

@class Playlist;

// ========================================
// A node representing a collection of ordered AudioStreams in a playlist
// TODO: Allow hierarchical playlists
// ========================================
@interface PlaylistNode : AudioStreamCollectionNode
{
	@private
	Playlist	*_playlist;
	BOOL		_playlistLoadedStreams;
}

- (id) initWithPlaylist:(Playlist *)playlist;

- (Playlist *) playlist;

@end