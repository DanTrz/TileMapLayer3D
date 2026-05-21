# Setting Up Auto_tile

## Step 1: Ensure you have a Texture loaded via the Manual Mode first
<img width="480" height="240" alt="image" src="https://github.com/user-attachments/assets/ac54144f-1030-48e9-9114-610b98e87c67" />

- You must have at a minimum a TileSet Texture that fits the recommended Auto-tile Terrain Templates 
- For TileMapLayer3D, you need a full 47 Tiles template with the 3x3 Format
- <img width="480" height="160" alt="image" src="https://github.com/user-attachments/assets/63e5e44e-fa73-4403-b5a3-9c51149aaa47" />
- The best explanation for Auto-Tile Terrain creation is still in the Godot 3.4 docs (but works perfectly with 4.7+)
See: https://docs.godotengine.org/en/3.4/tutorials/2d/using_tilemaps.html 

## Step 2: Change to Auto-Tile mode and create a new TileSet Resource
<img width="480" height="160" alt="image" src="https://github.com/user-attachments/assets/0cb29931-50f2-47b1-b6ce-c767ab2e1556" />

- Click the button "Create New" this will Link the Loaded Texture on Manual Mode to the Auto-Tile

## Step 3: Add Some Terrains (based on your Loaded Texture and TileSet)
<img width="480" height="160" alt="image" src="https://github.com/user-attachments/assets/05d4cb3e-81fc-42dd-922c-d268476d5aa0" />

- Just add a Name and choose a Colour. These Terrains will be what you use to "paint" your terrain.

## Step 4: Click "TileSet Terrain Editor" button - This will move you to a new Tab at the bottom panels in the Editor
<img width="480" height="200" alt="image" src="https://github.com/user-attachments/assets/c6d16e8f-d5e7-420e-84e9-30fe9e74fa43" />

- Make sure you choose "Paint" (Paint Properties) Option, then the following options:
- Paint Properties = "Terrains"
- Terrain set = "Terrain Set 0"
- Terrain = Select the Terrain you want to set up for Auto-Tile.

## Step 5: Now you need to activate all base tiles that are part of that Terrain by clicking on them
<img width="360" height="120" alt="image" src="https://github.com/user-attachments/assets/c3fece39-bbc5-4d6f-9efd-362fd500430f" />

## Step 6: Next step is to select what areas in your Tiles represent the terrain. You do that by painting the Terrain Color over the Texture Tiles, following the pre-determined Godot Auto-tile Terrain Templates 
<img width="360" height="120" alt="image" src="https://github.com/user-attachments/assets/1a20c0c1-dbe6-4551-be15-d51f7dde2c42" />

- For TileMapLayer3D, you need a full 47 Tiles template with the 3x3 Format
- You can watch this video that explains how to Define the correct Terrain Tiles for Auto-Tile and Paint Terrain Properties: See from minute 3:00 - https://youtu.be/LrsfgDyOAJs?si=vWavZWXs3REXc87E&t=181 
- <img width="360" height="120" alt="image" src="https://github.com/user-attachments/assets/63e5e44e-fa73-4403-b5a3-9c51149aaa47" />
- The best explanation for Auto-Tile Terrain creation is still in the Godot 3.4 docs (but works perfectly with 4.7+)
See: https://docs.godotengine.org/en/3.4/tutorials/2d/using_tilemaps.html


- Make sure you SAVE everything.

## After the Auto-Tile Terrain is created, you can go back to the TileMapLayer3D panel
<img width="360" height="120" alt="image" src="https://github.com/user-attachments/assets/73a9b78b-5eb5-4385-8d94-019e7235742d" />

- Select the Terrain in the List 
- Start painting with it.



