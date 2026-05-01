/*
  Warnings:

  - You are about to drop the column `boundary` on the `geofences` table. All the data in the column will be lost.
  - You are about to drop the column `location` on the `positions` table. All the data in the column will be lost.

*/
-- DropIndex
DROP INDEX "geofences_boundary_gist_idx";

-- DropIndex
DROP INDEX "positions_location_gist_idx";

-- AlterTable
ALTER TABLE "geofences" DROP COLUMN "boundary";

-- AlterTable
ALTER TABLE "positions" DROP COLUMN "location";
